#!usr/bin/env perl
use strict;
use warnings;
use 5.016;
use DDP;

package Local::Rm {
	use Class::XSAccessor {
		constructor => 'new',
		accessors   => [qw(target)]
	};
	
	sub execute {
	        my ($self, $command) = @_;
		my $root = $self->target;
		chomp $root;
		
		if ($command =~ /^\s*rm\s+
					(?:['"]*)
						([^'"]+)
					(?:['"]*\s*)
				/x
		) {
			my @pathes = split(' ', $1);
			say $pathes[0];
			foreach my $v (@pathes) {
				if ($v =~ /\{([^{}\s]+)\}$/) {
					say $1;
					my @list = split(',', $1);
					$v =~ s{\{([^{}\s]+)\}$}{};
					@list = map {$root."/".$v.$_} @list; 
					foreach my $u (@list) {
						say $u;	
						unlink $u or warn "Could not unlink $u: $!" if (-f $u);
					}	
				} elsif ($v =~ /\*$/) {#working!
					$v =~ s{\*$}{};
					my $dir = $v;
					$dir = $root."/".$dir;
					opendir(my $dh, $dir) || die "can't opendir $dir: $!"; 
					foreach my $target (<$dir/*>) {
						unlink $target or warn "Could not unlink $target: $!" if (-f $target); 		
					}	
					closedir($dh);		
				} else {
					my $target = $root."/".$v;
					unlink $target or warn "Could not unlink $target: $!" if (-f $target);
				}
			}
			return "Successfull deleting!";	
		}
	}

}1;






















