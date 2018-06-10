#!/usr/bin/env perl
use 5.016;
use feature 'switch';
use warnings;
no warnings 'experimental';
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use DDP; 
use Ls; use Cp; use Mv; use Rm; use Storage;

my $cv = AE::cv;
my $port = shift || 1234;
my $BUFFSIZE = 64;
tcp_server(undef, $port,
	sub {
		my $fh = shift or die "Cannot accept client: $!";
		my ($host, $port) = @_;
		my $hl; $hl = AnyEvent::Handle->new(
        		fh       => $fh,
        		on_error => sub {
            			shift;
            			my ($fatal, $msg) = @_;
            			warn "Error: [$msg]\n";
            			$cv->send;
        		},
        		on_eof => sub {
            			warn "Reached EOF\n";
            			$hl->destroy();
            			$cv->send;
        		}
    		);
		$hl->push_read(line => \&listener);	
	}
);

#sub reply {
#	my $h = shift;	
#	if (defined $_[0]) {
#		$h->push_write("OK ".(length($_[0])+1)."\n".$_[0]."\n");
#	} else {
#		my $err = $_[1];
#		$err =~ s/\n//gs;
#		$h->push_write("ERROR".$err."\n");
#	}
#}

sub listener {
	my ($h, $line) = @_;
	given ($line) {
		when (/^\s*ls/x) {
			say $line;
			my ($comm, $verbose) = $line =~ /^(\s*ls\s*[^\s]*)\s+(\d+)$/;	
			#print $h->{rbuf} if ($h->{rbuf});
			my $ls = Local::Ls->new(target => $h->{rbuf});
			my $out = $ls->execute($comm);
			$h->push_write("The content of directory:\n") if ($verbose > 0);
			$h->push_write($out."\n"); 
		}
		when(/^\s*rm\s+/) {
			#chomp $h->{rbuf};
			my $rm = Local::Rm->new(target => $h->{rbuf});
			my $out = $rm->execute($line);
			$h->push_write($out."\n");
		}
		when(/^\s*cp\s+/) { 
			my $cp = Local::Cp->new(target => $h->{rbuf});
			my $out = $cp->execute($line);
			$h->push_write($out."\n");
		}
		when(/^\s*mv\s+/) {
			say $line; 
			my $mv = Local::Mv->new(target => $h->{rbuf});
			my $out = $mv->execute($line);
			$h->push_write($out."\n");
		}
		when (/^\s*(mkdir|rmdir|touch)\s*/) {
			#chomp $h->{rbuf};
			my $st = Local::Storage->new(target => $h->{rbuf});
			my $out = $st->execute($line);
			#my $out = $st->make_dir($line);
			$h->push_write($out."\n");
		}
		when (/^\s*put\s(\d+)\s([^\s]+)$/) {
	                say $line;
	                say $1, " ", $2;
	                my ($size, $name) = ($1, $2);
	                my $left = $size;
			open(my $fh, '>:raw', "$name") or $cv->croak("Failed to open file: $!");
	                my $body; $body = sub {
	                        $h->unshift_read(
	                                chunk => $left > $BUFFSIZE ? $BUFFSIZE : $left, sub {
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
        	}
		when (/^\s*get\s([^\s]+)$/) {
			my $path = $1; my $filename;
			$filename = $1 if ($path =~ /([^\/]+)$/);	
			my $pos = length($path) - length($filename) - 1;
			$path = substr($path, 0, $pos);
			chdir $path or die $!;
			my $size = -s $filename;
			defined $size or $cv->croak("$!");;
			#say $size;
			$h->push_write("get $size $filename"."\n");
	
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
                                                        $h->push_write($wr);
                                                        if ($h->{wbuf}) {
                                                        	$h->on_drain(
                                                                	sub {
                                                                        	$h->on_drain(undef);
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
		when(/DELETE/) {
			say "CURL";
		}
		default {
		#	reply->($h, "Unknown command");	
		}
	}
	
	$h->push_read(line => \&listener);
}

$cv->recv;



























