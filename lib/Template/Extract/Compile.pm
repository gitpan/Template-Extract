# $File: //member/autrijus/Template-Extract/lib/Template/Extract/Compile.pm $ $Author: autrijus $
# $Revision: #1 $ $Change: 10075 $ $DateTime: 2004/02/16 16:50:48 $

package Template::Extract::Compile;
$Template::Extract::Compile::VERSION = '0.36';

use 5.006;
use strict;
use warnings;
use Template::Parser;

our ( $DEBUG, $EXACT );
my ( $paren_id, $block_id );

=head1 NAME

Template::Extract::Compile - Compile TT2 templates into regular expressions

=head1 SYNOPSIS

    use Template::Extract::Compile;

    my $template = << '.';
    <ul>[% FOREACH record %]
    <li><A HREF="[% url %]">[% title %]</A>: [% rate %] - [% comment %].
    [% ... %]
    [% END %]</ul>
    .
    my $regex = Template::Extract::Compile->new->compile($template);

    open FH, '>', 'stored_regex' or die $!;
    print FH $regex;
    close FH;

=head1 DESCRIPTION

This module utilizes B<Template::Parser> to transform a TT2 template into
a regular expression suitable for the B<Template::Extract::Run> module.

=head1 METHODS

=head2 new()

Constructor.  Currently takes no parameters.

=head2 compile($template)

Returns the regular expression compiled from C<$template>.

=cut

sub new {
    my $class = shift;
    my $self = {};
    return bless($self, $class);
}

sub compile {
    my ( $self, $template ) = @_;

    $self->_init();

    if ( defined $template ) {
	my $parser = Template::Parser->new(
	    {
                PRE_CHOMP  => 1,
		POST_CHOMP => 1,
	    }
	);

	$parser->{FACTORY} = ref($self);
	$template = $$template if UNIVERSAL::isa( $template, 'SCALAR' );
	$template =~ s/\n+$//;
	$template =~ s/\[%\s*(?:\.\.\.|_|__)\s*%\]/[% \/.*?\/ %]/g;
	$template =~ s/\[%\s*(\/.*?\/)\s*%\]/'[% "' . quotemeta($1) . '" %]'/eg;

	return $parser->parse($template)->{BLOCK};
    }
    return undef;
}

# initialize temporary variables
sub _init {
    $paren_id = 0;
    $block_id = 0;
}


# utility function to add regex eval brackets
sub _re { "(?{\n    @_\n})" }

# --- Factory API implementation begins here ---

sub template {
    my $regex = $_[1];

    $regex =~ s/\*\*//g;
    $regex =~ s/\+\+/+/g;
    $regex = "^$regex\$" if $EXACT;

    # Deal with backtracking here -- substitute repeated occurences of
    # the variable into backtracking sequences like (\1)
    my %seen;
    $regex =~ s{(                       # entire sequence [1]
        \(\.\*\?\)                      #   matching regex
        \(\?\{                          #   post-matching regex...
            \s*                         #     whitespaces
            _ext\(                      #     capturing handler...
                \(                      #       inner cluster of...
                    \[ (.+?) \],\s*     #         var name [2]
                    \$.*?,\s*           #         dollar with ^N/counter
                    (\d+)               #         counter [3]
                \)                      #       ...end inner cluster
                (.*?)                   #       outer loop stack [4]
            \)                          #     ...end capturing handler
            \s*                         #     whitespaces
        \}\)                            #   ...end post-maching regex
    )}{
        if ($seen{$2,$4}) {             # if var reoccured in the same loop
            "(\\$seen{$2,$4})"          #   replace it with backtracker
        } else {                        # otherwise
            $seen{$2,$4} = $3;          #   register this var's counter
            $1;                         #   and preserve the sequence 
        }
    }gex;
    return $regex;
}

sub foreach {
    my $regex = $_[4];

    # find out immediate children
    my %vars = reverse (
	$regex =~ /_ext\(\(\[(\[?)('\w+').*?\], [^,]+, \d+\)\*\*/g
    );
    my $vars = join( ',', map { $vars{$_} ? "\\$_" : $_ } sort keys %vars );

    # append this block's id into the _get calling chain
    ++$block_id;
    ++$paren_id;
    $regex =~ s/\*\*/, $block_id**/g;
    $regex =~ s/\+\+/*/g;

    return (
        # sets $cur_loop
        _re("_enter_loop($_[2], $block_id)") .
        # match loop content
        "(?:\\n*?$regex)++()" .
        # weed out partial matches
        _re("_ext(([[$_[2],[$vars]]], \\'leave_loop', $paren_id)**)") .
        # optional, implicit newline
        "\\n*?"
    );
}

sub get {
    return "(?:$1)" if $_[1] =~ m{^/(.*)/$};

    ++$paren_id;

    # ** is the placeholder for parent loop ids
    return "(.*?)" . _re("_ext(([$_[1]], \$$paren_id, $paren_id)\*\*)");
}

sub set {
    ++$paren_id;

    my $val = $_[1][1];
    $val =~ s/^'(.*)'\z/$1/;
    $val = quotemeta($val);

    my $parents = join(
        ',', map {
            $_[1][0][ $_ * 2 ]
        } ( 0 .. $#{ $_[1][0] } / 2 )
    );
    return '()' . _re("_ext(([$parents], \\\\'$val', $paren_id)\*\*)");
}

sub textblock {
    return quotemeta( $_[1] );
}

sub block {
    my $rv = '';
    foreach my $chunk ( map "$_", @{$_[1]||[]} ) {
        $chunk =~ s/^#line .*\n//;
        $rv .= $chunk;
    }
    return $rv;
}

sub quoted {
    my $rv = '';

    foreach my $token ( @{ $_[1] } ) {
	if ( $token =~ m/^'(.+)'$/ ) {    # nested hash traversal
	    $rv .= '$';
	    $rv .= "{$_}" foreach split( /','/, $1 );
	}
	else {
	    $rv .= $token;
	}
    }

    return $rv;
}

sub ident {
    return join( ',', map { $_[1][ $_ * 2 ] } ( 0 .. $#{ $_[1] } / 2 ) );
}

sub text {
    return $_[1];
}

# debug routine to catch unsupported directives
sub AUTOLOAD {
    $DEBUG or return;

    require Data::Dumper;
    $Data::Dumper::Indent = 1;

    our $AUTOLOAD;
    print "\n$AUTOLOAD -";

    for my $arg ( 1 .. $#_ ) {
	print "\n    [$arg]: ";
	print ref( $_[$arg] )
	  ? Data::Dumper->Dump( [ $_[$arg] ], ['__'] )
	  : $_[$arg];
    }

    return '';
}

1;

=head1 SEE ALSO

L<Template::Extract>, L<Template::Extract::Run>

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>

=head1 COPYRIGHT

Copyright 2004 by Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
