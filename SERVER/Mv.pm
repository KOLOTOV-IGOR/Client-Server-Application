#!/usr/bin/env perl
use strict;
use warnings;
use 5.016;

package Local::Mv {
	use Class::XSAccessor {
		constructor => 'new',
		accessors   => [qw(target)]
	};
	
	sub execute {
	        my ($self, $command) = @_;
		my $root = $self->target;
		chomp $root;
		if ($command =~ /^\s*mv\s+
					(?:['"]*)
						([^'"]+)
					(?:['"]*\s*)
				$/x) 
		{
			my @args =split(' ', $1);
			return "Error! You need two arguments for mv-command" if (@args < 2);
			my $source = join('/', $root, $args[0]);
		        my $target = join('/', $root, $args[1]);
			say $source;
			say $target;
			if (-d $target) {
				my $file;
				if ($args[0] =~ /\/?([^\/]*)$/) {
					$file = $1;
				}
				say $file;
				$target = $target."/".$file;
			}
			rename $source, $target or die "Error in renaming!";
			return 1;
		} 
	}
}1;



















