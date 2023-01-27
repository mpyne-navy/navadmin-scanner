#!/usr/bin/env perl

# Breaks a NAVADMIN record message (passed as a filename on the command line)
# into a header and then a main body.

use v5.28;

use feature 'signatures';

use Mojo::File;
use Mojo::JSON qw(encode_json);
use List::Util qw(first);

sub usage()
{
    say <<~EOF;
        $0 <path-to-navadmin.txt>

        Reads the given NAVADMIN and spits out a JSON array containing two
        strings in order, the header and then the message body.
        EOF
    exit 1;
}

sub split_up_navadmin($text)
{
    my ($head, $body);
    my $in_head = 1;

    my @lines = split("\n", $text);
    while (defined (my $line = shift @lines)) {
        # Look for header fields getting jammed together, this risks mixing
        # with the body
        if ($in_head && $line =~ m,// *[^ ], && $line !~ m, *//[\r ]*$,) {
            my ($field, $rest) = split(/\/\/ */, $line, 2); # split into 2 fields max
            $field = "$field//";
            $line = $field;
            unshift @lines, $rest;

            # current field in $line should now be guaranteed to have no text after //
        }

#       say "cur line: $line (", scalar @lines, " more to read)";

        if ($in_head && (
                $line =~ m,^(GENTEXT/)?[rR][mM][kK][sS]/, ||
                $line =~ m,^(GENTEXT/)?REMARKS/,          ||
                # maybe they just started with the text...
                $line =~ m,^RMKS1\.,                      ||
                $line =~ m,^1\.,
            ))
        {
            $in_head = 0; # switch to reading body
        }

        if ($in_head) {
            $head .= "$line\n";
        } else {
            $body .= "$line\n";
        }
    }

    if (!$body) {
        # Something went wrong, return error exit code
        exit 1;
    }

    return ($head, $body);
}

sub decode_msg_head($head)
{
    # for now, just split every non-narrative line by first word
    my %fields = (
        REF => [ ],
    );

    my %single_line_fields = map { ($_, 1) }
        qw(REF MSGID);

    my @lines = split(/\r?\n/, $head);
    my $in_field = 0;
    my $partial_field = '';

    my $trim = sub($text) {
        my $res = $text;
        $res =~ s/^ +//;
        $res =~ s/ +$//;
        $res;
    };

    # sets REF text amplification e.g. 'REF B IS MILPERSMAN 1200-200'
    my $set_ref_ampn = sub($id, $ampn) {
        my $ref = first { $_->{id} eq $id } @{$fields{REF}};
        die "Unknown field $id" unless $ref;
        $ref->{ampn} = $ampn;
    };

    my $set_field = sub($field, $payload) {
        my $val = $trim->($payload);

        if ($field eq 'REF') {
            my ($id, $info) = split(/\//, $val, 2);
            push @{$fields{REF}}, { id => $id, text => $info };
        } elsif ($field eq 'NARR') {
            my @refs = split(/REF ([A-Z]+) /, $val);
            # this should give us a result like '', 'A', 'IS NAVADMIN 304/17', 'B', etc.
#           say STDERR encode_json(\@refs);
            if (((scalar @refs) % 2) != 1 || $refs[0] ne '') {
                say STDERR "Unrecognized NARR";
                return;
            }

            shift @refs;
            my %ref_ampns = @refs; # convert to hash
            if (my $bad_key = first { length $_ > 1 } keys %ref_ampns) {
                say STDERR "Key $bad_key is malformed in NARR fields";
                return;
            }

            for my $ampn_id (keys %ref_ampns) {
                my $ampn = $trim->($ref_ampns{$ampn_id});
                $ampn =~ s/^IS //; # Sometimes not present...
                $ampn =~ s/,.*$//; # Remove anything after a comma if present
                $set_ref_ampn->($ampn_id, $ampn);
            }
        } else {
            $fields{$field} = $val;
        }
    };

    for my $line (@lines) {
        if ($in_field) {
            # if we're reading a slash-separated field, append lines to field
            # until it ends in //.
            $partial_field .= $line;
            if ($line =~ m,// *$,) {
                # end of field found

                my ($field, $payload) = split(/ *\/ */, $partial_field, 2);
                $set_field->($field, $payload);
                $in_field = 0;
                $partial_field = '';
            }

            next;
        }

        # we weren't already in a field, check for common line types
        next if $line =~ /^$/;
        next if $line =~ /^ *PASS TO OFFICE/;
        next if $line =~ /^ *CLASSIFICATION:/;
        next if $line =~ /^ *(BT|UNCLAS|ROUTINE|R |O |P )/;

        # seems to be a real field, see if the first separator is a space or a
        # slash.  If a slash, look for a double-slash as the field terminator.
        if ($line =~ /^[A-Z]+ /) {
            # space
            my ($field, $payload) = split(' ', $line, 2);
            $set_field->($field, $payload);
        } elsif ($line =~ /^[A-Z]+ *\//) {
#           say STDERR "line has a slash [$line]";
            # slash
            my ($field_id) = (split(/\//, $line, 2)); # ignore second part

#           say STDERR "\tField is $field_id";

            if ($line !~ m,// *$, && !exists $single_line_fields{$field_id}) {
                # this line only has part of the field. Don't parse until we
                # have the whole field
#               say STDERR "\tline is partial [$line]";
                $in_field = 1;
                $partial_field = $line;
                next;
            }

            # Check for things like SUBJ//blah blah// (first // should be /)
            $line =~ s,^([A-Z]+)//([A-Z]),\1/\2,;

            # Got the whole field here, read it
            my ($field, $payload) = split(/ *\/ */, $line, 2);
            $set_field->($field, $payload);
        }
    }

    return \%fields;
}

sub read_navadmin($path)
{
    my $content = $path->slurp;
    my ($head, $body) = split_up_navadmin($content);
    my $fields = decode_msg_head($head);
    say encode_json({ head => $head, fields => $fields, body => $body });
}

my @files;

if (@ARGV) {
    # Create Mojo::File for each path param
    @files = map { Mojo::File->new($_) } @ARGV;
} else {
    usage();
    # List all NAVADMINs if no file specified
#   @files = Mojo::File->new('NAVADMIN')->list_tree->grep(qr/\.txt$/)->each;
}

foreach my $path (@files) {
    read_navadmin($path);
}
