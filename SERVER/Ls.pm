#!/usr/bin/env perl
use strict;
use warnings;
use 5.016;

package Local::Ls {
	use Class::XSAccessor {
		constructor => 'new',
		accessors   => [qw(target)],
	};

	sub execute {
		my $self    = shift;
		my $command = shift;
		my $target  = $self->target;
		chomp $target;
		return if ($command =~ /\/?\.{2}\/?/);
		my $res;
	        if ($command =~ m{
				^\s*ls\s*$
				}x
		) {
			$res = qx(ls -lA $target);
			return $res;
		} elsif ($command =~ /^\s*ls\s*
					([^\s]*)	
				/x
		) {
			#say $1;
			my $path = join('/', $target, $1);
			#say $path;
			#my $res = system("ls -lA ".$path);
			if (-f $path) {
				return "This is a file!";
			}
			$res = qx(ls -lA $path) or return $!;
			return $res;
		}
		
	}
	
}1;


