#!usr/bin/env perl
use strict;
use warnings;
use 5.016;
use feature 'switch';
use warnings;
no warnings 'experimental';
use DDP;

package Local::Storage {
	use File::Path qw(make_path remove_tree);
	use Class::XSAccessor {
		constructor  => 'new',
		accessors    => [qw(target)]
	};
	
	sub show_file_content {
		my ($self, $command) = @_;
		if ($command =~ /^\s*cat\s+
				(?:['"]*\s*)
					((\w+(\/\w+)*)\/{1}){0,1}(\w*\.\w+)\s*
				(?:['"]*\s*)
				$/x) 
		{
			...
		}	
	}

	sub create_file {
		my ($self, $command) = @_;
		my $root = $self->target;
		chomp $root;
		return "Don't use /../" if ($command =~ /\/?\.{2}\/?/);
		if ($command =~ /^\s*touch\s+([^'"\s]+)\s*$/x) {
			say "Yes";	
			my $path = $root."/".$1;
			say $path;
			open(my $fh, '>raw', $path) or do { return "touch error!" };
			#syswrite($fh, $2);
			close $fh or do { warn $! };
			return "touch";					
		}	
		elsif ($command =~ /^\s*touch\s+([^'"\s]+)
					(?:["'\s]*)
						([^'"]+)
					(?:['"\s]*)
				/x	
		) {
			say $1; say $2;
			my $path = $root."/".$1;
			say $path;
			open(my $fh, '>raw', $path) or do { return "touch error!" };
			syswrite($fh, $2);
			close $fh or do { warn $! };
			return "touch";					
		}
	} 

	sub make_dir {
		my ($self, $command) = @_;
		my $root = $self->target;
		chomp $root;
		return if ($command =~ /\/?\.{2}\/?/);	
		if ($command =~ /^\s*mkdir\s+(?:['"]?\s*)([^\s'"{}]*)\s*(?:['"]?\s*)$/ ) {
			my $ndir = join('/', $root, $1);
			say $ndir;
			make_path($ndir, { verbose => 0 }) or die $!;
		} elsif ($command =~ /^\s*mkdir\s+
					(?:['"]?\s*)
						(([^\s'"{}\/]*\/)+)
						{
							(([^\s'"{}]+,?)+)
						}
						\s*
					(?:['"]?\s*)$
				     /x) 
		{
			#say $1; say $3;
			my @list = split(/,/, $3);
			for my $v (@list) {
				say $v;
				my $rdir = join('/', $root, $1, $v);
				say $rdir;
				make_path($rdir, {verbose => 0}) or die $!;
			}
		}	
	}
	
	sub remove_dir {
		my ($self, $command) = @_;
		my $root = $self->target;
		chomp $root;
		return if ($command =~ /\/?\.{2}\/?/);	
		if ($command =~ /^\s*rmdir\s+(?:['"]?\s*)([^\s'"{}\*]*)\s*(?:['"]?\s*)$/ ) {
			my $rdir = join('/', $root, $1);
			say $rdir;
			remove_tree($rdir, { verbose => 0 }) or die $!;
		} elsif ($command =~ /^\s*rmdir\s+
					(?:['"]?\s*)
						(([^\s'"{}\/\*]*\/)+)
						{
							(([^\s'"{}]+,?)+)
						}
						\s*
					(?:['"]?\s*)$
				     /x) 
		{
			#say $1; say $3;
			my @list = split(/,/, $3);
			for my $v (@list) {
				say $v;
				my $rdir = join('/', $root, $1, $v);
				say $rdir;
				remove_tree($rdir, {verbose => 0}) or die $!;
			}
		} elsif ($command =~ /^\s*rmdir\s+
					(?:['"]?\s*)
						(([^\s'"{}\/]*\/)+) \*
					(?:['"]?\s*)
				     /x)
		{
			my $dir = $root.'/'.$1;
			#say $dir;
			foreach my $v (<$dir/*>) {
				remove_tree($v) or die $! if (-d $v);
			}
		}	
	}

	sub curl_remove {
		my ($self, $h, $path) = @_;
		my $root = $self->target;
		chomp $root;
		if ($root.$path =~ /\/?\.{2}\/?/) {
			$h->push_write("HTTP/1.1 400 Bad Request\nContent-Length: 0\nx-size: 0\n\n");	
		}
		my $target = $root."/".$path;
		unlink $target or return "Could not unlink $target: $!" if (-f $target);
		return 1;
	}
		
	sub curl_get {
		my ($self, $h, $path) = @_;
		my $root = $self->target;
		chomp $root;
		if ($root.$path =~ /\/?\.{2}\/?/) {
			$h->push_write("HTTP/1.1 400 Bad Request\nContent-Length: 0\nx-size: 1\n\n");	
		}
		my $BUFFSIZE = 64;	
					
		if (-f $root."/"."$path") {
			my $size = -s $path;
			defined $size or return;
			open(my $f, '<:raw', $root."/"."$path") or do {
				$h->push_write("HTTP/1.1 404 Not Found\nContent-Length: 0\n\n");
			};	
			my $rf; $rf = AnyEvent::Handle->new(
				fh => $f,
				max_read_size => $BUFFSIZE, 
				read_size => $BUFFSIZE 
			);
			#$h->push_write("HTTP/1.1 100 Continue\nContent-Length: 0\n\n"); 
			my $left = $size;
			$h->push_write("HTTP/1.1 200 OK\nContent-Length: $size\n\n");
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
		} elsif (-d $root."/".$path) {
			my $out = qx(ls -lA $root$path);
			my $size = length($out);
			$h->push_write("HTTP/1.1 200 OK\nContent-Length: $size\n\n");
			$h->push_write($out);
		}
	}

	sub curl_put($$$) {
		my ($self, $h, $path) = @_;
		my $root = $self->target;
		chomp $root;
		if ("$root/$path" =~ /\/?\.{2}\/?/) {
			$h->push_write("HTTP/1.1 400 Bad Request\nContent-Length: 0\nx-size: 2\n");	
		}
		my $BUFFSIZE = 1024;	
		say "$root/$path";	
		#my $left = $size;

		$h->push_write("HTTP/1.1 100 Continue\nContent-Length: 0\n\n");
		$h->unshift_read( line => qr/\015?\012\015?\012/, sub {
			my $adr = shift;
			my $line = shift;
			say $line;
			my @header = split(/\015?\012/, $line); 			
			
			my $size;
			my @c = grep(/Content-Length:\s+/i, @header);
			#say $c[0];
			$size = $1 if ($c[0] =~ /Content-Length:\s+(\d+)$/i);
			say $size;
			defined $size or do {
				$h->push_write("HTTP/1.1 400 Bad Request\nContent-Length: 0\nx-bad-size: 3\n\n");
				return;
			};
			open(my $fh, '>:raw', "$root/$path") or do {
				$h->push_write("HTTP/1.1 404 Not Found\nContent-Length: 0\n\n");
				return;
			};
			my $left = $size;
			my $body; $body = sub {
				$h->unshift_read(chunk => $left > $BUFFSIZE ? $BUFFSIZE : $left, sub {
						my $rd = $_[1];
						#say $rd;
						$left -= length $rd;
						syswrite($fh, $rd);
						if ($left == 0) {
							undef $body;
							close $fh;
							$h->push_write("HTTP/1.1 200 OK\nContent-Length: 0\n\n");
						} else {
							$body->();
						}
					}
				);
			}; $body->();
			
			#$h->push_write("HTTP/1.1 200 OK\nContent-Length: 0\n\n");
		});
	}

	sub curl_post {
		my ($self, $h) = @_;
	}

	sub execute {
		my ($self, $command) = @_;
		given ($command) {
			when (/^\s*mkdir\s+/) {
				$self->make_dir($command);
				return "You make directory!";
			}
			when (/^\s*rmdir\s*/) {
				$self->remove_dir($command);
				return "You remove directory!";
			}
			when (/^\s*touch\s+/) {
				$self->create_file($command);
			}
		}
	}	
}1;









