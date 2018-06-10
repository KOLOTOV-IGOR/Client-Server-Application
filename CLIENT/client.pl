#!/usr/bin/env perl
use AnyEvent::Socket;
use 5.016;
use warnings;
use feature 'switch';
no warnings 'experimental';
use AnyEvent::Handle;
use AnyEvent::ReadLine::Gnu;
use Getopt::Long;
Getopt::Long::Configure("Bundling");

sub usage {
        say "Usage:";
        say "\t $0 [-h] [-v] host:port /path/to/the/somewhere";
        say "\t -h | --help    - print usage and exit";
        say "\t -v | --verbose - be verbose";
	say "\t if you want to leave server input exit in command line";
}

my $cv = AE::cv;
my $verbose = 0;
GetOptions( 'h|help' => sub { die &usage }, 'v|verbose+' => \$verbose);

my $arg  = shift;
my $root = shift;
die &usage if (!defined $arg or !defined($root)); 
my ($host, $port) = $arg =~ /^(\w+|(?:\d{1,3})(?:\.\d{1,3}){3}):(\d+)$/;


#my $cv = AE::cv;
my $hl; $hl = AnyEvent::Handle->new(
	connect => [$host, $port],
	on_prepare => sub {
		my $h = shift;
		warn "Connecting to the host $host on port = $port\n";
	},
	on_connect_error => sub {
		my ($h, $msg) = @_;	
		warn "Error: $msg to the host $host on port $port\n";
		exit;
	},
	on_error => sub {
		my ($h, $fatal, $msg) = @_;
		warn "FATAL ERROR! The connection is terminated!";
		$h->destroy();
		exit;
	},
	on_eof => sub {
		my $h =shift;
		warn "Connection was closed!\n";
		$h->destroy();
		$cv->send;
	},
);
my $BUFFSIZE = 64;
my $rl; $rl = AnyEvent::ReadLine::Gnu->new(
	prompt  => '>',
	on_line => sub {
		my $command = shift;
		$rl->print("you entered: $command\n");
		$rl->add_history($command) if ($command =~ /\S/);
		given($command) {
			when (/\s*exit\s*/i) {
				#$cv->send;#Pipe breaks!
				#$rl->WriteHistory('history') or $cv->croak($!);
				$rl->print("Bye!\n");
				exit(0);
			}
			when (/^\s*!(.+)$/x) {
				$rl->print("shell escape:\n") if ($verbose == 1);
				$rl->print("You've done shell escape:\n") if ($verbose > 1);
				$rl->hide();
				system($1);# or $cv->croak("$!");
				$rl->show();
			}
			when (/^\s*ls\s*/x) {
				$hl->push_write($command." $verbose"."\n".$root."\n");
				$hl->push_read(line => \&listing);
			}
			when (/^\s*rm\s+/) {
				$hl->push_write($command."\n".$root."\n");
				$hl->push_read(line => \&respond);
			}
			when (/^\s*cp\s+/) {
				$hl->push_write($command."\n".$root."\n");
				$hl->push_read(line => \&respond) if ($verbose > 0);
			}
			when (/^\s*mv\s+/) {
				$hl->push_write($command."\n".$root."\n");
				$hl->push_read(line => \&respond) if ($verbose > 0);
			}
			when (/^\s*(mkdir|rmdir|touch)\s+/) {
				$hl->push_write($command."\n".$root."\n");
				$hl->push_read(line => \&respond);
			}
			when (/^put\s+([^\s]+)$/) {
	                        my $filename = $1;
	                        $rl->print("name of file: $filename\n");
	                        my $size = -s $filename;
	                        defined $size or return;
				my $path = $root."/".$filename;
	                        $hl->push_write("put $size $path"."\n");
	                        #Here needs the answer from server!
	
	                        open(my $f, '<:raw', $filename) or $cv->croak("Failed to open file $filename: $!");
	                        my $rf; $rf = AnyEvent::Handle->new(
	                                fh => $f,
	                                max_read_size => $BUFFSIZE,
	                                read_size => $BUFFSIZE
	                        );
	                        my $left = $size;
	                        my $do; $do = sub {
	                                if ($left > 0) {
	                                        $rf->push_read(chunk => $left > $BUFFSIZE ? $BUFFSIZE : $left,
	                                                sub {
	                                                        my $wr = $_[1];
	                                                        $left -= length $wr;
	                                                        $hl->push_write($wr);
	                                                        if ($hl->{wbuf}) {
	                                                                $hl->on_drain(
	                                                                        sub {
	                                                                                $hl->on_drain(undef);
	                                                                                $do->();
	                                                                        }
	                                                                );
	                                                        } else {
	                                                                #successfully 
	                                                                $do->();
	                                                        }
	                                                }
	                                        );
	                                } else {
	                                        $rf->destroy();
	                                }
	                        }; $do->();
	                }
			when (/^\s*get\s+([^\s]+)$/) {
	                        my $filename = $1;#file name with path
	                       	my $path = $root."/".$filename;	
				$hl->push_write("get $path"."\n");
				$hl->unshift_read(line => \&get_file);
				#$hl->push_read(line => \&get_file);#With this command get doesn't work after ls!
				$rl->print("File is downloaded!\n"); 	
			}
			default {
				$rl->print("You input the wrong command!\n");
			}

		}	
	}		
);

$rl->Attribs->{completion_entry_function} = $rl->Attribs->{list_completion_function};
$rl->Attribs->{completion_word} = [qw(ls mv cp rm put get touch mkdir rmdir)];
$rl->using_history();
#$rl->ReadHisroty('history') or $cv->croak($!);

sub get_file {
	my ($h, $line) = @_;
	#$rl->print($line);
	#$rl->print("File starts downloading.") if (defined $line);
	my $size; my $name;
	if ($line =~ /^get\s(\d+)\s([^\s]+)$/) {
		$size = $1;
		$name = $2;	
	}
	$rl->print($size." ".$name."\n");

	my $left = $size;
        open(my $fh, '>:raw', "$name") or $cv->croak("Failed to open file: $!");
        my $body; $body = sub {
        $h->unshift_read(chunk => $left > $BUFFSIZE ? $BUFFSIZE : $left, sub {
	        	my $rd = $_[1];
			$left -= length $rd;
	 		syswrite($fh, $rd);
	                if ($left == 0) {
	                	undef $body;
				close $fh;
			} else {
				$body->();
			}
		}
	);
	}; $body->();

	#$rl->print("File is downloaded!");
	#$h->push_read(line => \&get_file);
}

sub respond {
	my ($h, $line) = @_;
	$rl->hide();	
	say $line;
	$rl->show();
	#$h->push_read(line => \&respond);
}

sub listing {
	my ($h, $line) = @_;
	$rl->hide();	
	say $line;
	$rl->show();
	$h->push_read(line => \&listing);#Without this ls will output only one string!
}

$cv->recv;

























