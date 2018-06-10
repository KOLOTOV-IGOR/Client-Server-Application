#!/usr/bin/env perl
use warnings;
use 5.016;
use File::Copy;

package Local::Cp {
	use Class::XSAccessor {
		constructor => 'new',
		accessors   => [qw(target)]
	};

	sub execute {
	        my ($self, $command) = @_;
		my $root = $self->target;
		chomp $root;
		if ($command =~ /
					^\s*cp\s+(?:['"]*)
						([^'"]+)
					(?:['"]*\s*)*$
				/x
		) 
		{
			return "Don't use .. in the path!" if ($1 =~ /\/?\.{2}\/?/);
			my @args =split(' ', $1);
			return "Error! You need two arguments for cp-command!" if (@args < 2);
			my $source = join('/', $root, $args[0]);
		        my $target = join('/', $root, $args[1]);
			say $source;
			say $target;
			my $res = system("cp $source $target");
	        	return "$source -> $target";
		} 
	}


}1;



