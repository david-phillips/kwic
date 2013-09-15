use strict;
use warnings;
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Pod::Usage;
use File::Basename qw(fileparse);

=head1 NAME

kwic.pl - A regex KWIC concordancer

=head1 SYNOPSIS

perl kwic.pl [options] <pattern> <dir>

options:

  --help         Print this message and exit
  --sort         Sort the output by keyword
  --filenames    Print full relative path to file
  --basenames    Print basenames of files only
  --window=N     Override the default window size of 20
=cut


my $WINDOW_SIZE     = 20;
my $SORT_BY_KEYWORD = 0;
my $MAX_KEYWORD_LEN = 0;
my $MAX_FNAME_LEN   = 0;
my $FILENAMES;
my $BASENAMES;

# Parse command line
my $help;
GetOptions("help"      => \$help,
           "sort"      => \$SORT_BY_KEYWORD,
           "filenames" => \$FILENAMES,
           "basenames" => \$BASENAMES, 
           "window=i"  => \$WINDOW_SIZE);

pod2usage(1) if $help;
pod2usage(1) if @ARGV < 2;

##
#
# Main Program
#
##
my ($pattern, $dir) = @ARGV;
my $kwic_lines_unformatted = search_dir($pattern, $dir);
my $kwic_lines_formatted   = format_kwic_lines($kwic_lines_unformatted);
for my $line (@$kwic_lines_formatted) {
    print $line->{fname} . "\t" if ($FILENAMES || $BASENAMES);
    print $line->{lhs}
        . $line->{keyword}
        . $line->{rhs}
        . "\n";
}


##
#
# Returns arrayref of unformatted KWIC lines for given dir.
# Delegates to search_file()
#
##
sub search_dir {
    my ($pattern, $dir) = @_;
    $pattern = "($pattern)" unless $pattern =~ /^\(.*\)$/;
    my @kwic_lines_for_dir = ();
    my @agenda = `find -L $dir`;
    for my $fname (@agenda) {
        chomp $fname;
        next unless -f $fname;
        my $kwic_lines_for_file = search_file($pattern, $fname);
        @kwic_lines_for_dir = (
            @kwic_lines_for_dir,
            @$kwic_lines_for_file
        );
    }
    return \@kwic_lines_for_dir;
}


##
#
# Returns arrayref of unformatted KWIC lines for given file.
# Delegates to search_line()
#
##
sub search_file {
    my ($pattern, $fname) = @_;
    open(my $input_fh, '<', $fname)
        or die "Failed to open $fname: $!\n";
    my @kwic_lines_for_file = ();
    for my $line (<$input_fh>) {
		$line =~ s/\t/    /g;
        my $kwic_lines = search_line($pattern, $line, $fname);
        @kwic_lines_for_file = (
            @kwic_lines_for_file,
            @$kwic_lines
        );
    }
    return \@kwic_lines_for_file;
}


##
#
# Returns arrayref of unformatted KWIC lines for given line.
# We rely on split's ability to return delims for tokenization.
#
##
sub search_line {
    my ($pattern, $line, $fname) = @_;
    # if line contains N pattern
    # matches we produce N kwic lines
    chomp $line;
    my @kwic_lines = ();
    my @tokens = split(/$pattern/, $line);
    for (my $i = 0; $i < @tokens; ++$i) {
        my $keyword = $tokens[$i];
		# only visit split delimiters
        next unless ($i % 2 == 1);
        $MAX_KEYWORD_LEN = length $keyword if
                           length $keyword > $MAX_KEYWORD_LEN;
        my $lhs = join('', @tokens[0..$i-1]);
        my $rhs = join('', @tokens[$i+1..$#tokens]);
        my $kwic_line = {
            lhs => $lhs,
            keyword => $keyword,
            rhs => $rhs
        };
        my $display_fname;
        if ($FILENAMES) {
            $display_fname = $fname;
        } elsif ($BASENAMES) {
            $display_fname = fileparse($fname);
        }
        if ($FILENAMES || $BASENAMES) {
            $MAX_FNAME_LEN = length $display_fname if
                             length $display_fname > $MAX_FNAME_LEN;
            $kwic_line->{fname} = $display_fname;
        }
        push(@kwic_lines, $kwic_line);
    }
    return \@kwic_lines;
}


##
#
# Returns arrayref of formatted KWIC lines (delegates to format_kwic_lines)
#
##
sub format_kwic_lines {
    my ($lines, $maxlen) = @_;
    if ($SORT_BY_KEYWORD) {
        $lines = [
            sort {
                $a->{keyword} cmp $b->{keyword}
            } @$lines
        ];
    }
    return [
        map {
            format_kwic_line($_, $maxlen)
        } @$lines
    ];
}


##
#
# Returns a formatted KWIC line by padding the
# line components with whitespace as needed.
#
##
sub format_kwic_line {
    my ($line) = @_;
    # pad the keyword with whitespace
    my $keyword_border_len = 2;
    $MAX_KEYWORD_LEN++ if $MAX_KEYWORD_LEN % 2;
    my $padlen = ($MAX_KEYWORD_LEN - length $line->{keyword}) / 2;
    my $lpad = ' ' x ($padlen + $keyword_border_len);
    my $rpad = ' ' x ($padlen + $keyword_border_len);
    $line->{keyword} .= ' ' if (length $line->{keyword}) % 2;
    my $formatted_keyword = $lpad
                          . $line->{keyword}
                          . $rpad;

    # truncate or pad lhs to window size
    my $lhs_len = length $line->{lhs};    
    my $formatted_lhs = $line->{lhs};
    if ($lhs_len > $WINDOW_SIZE) {
        $formatted_lhs = substr($line->{lhs}, $lhs_len - $WINDOW_SIZE);
    } elsif ($lhs_len < $WINDOW_SIZE) {
        $formatted_lhs = (' ' x ($WINDOW_SIZE - $lhs_len)) . $line->{lhs}
    }
    # truncate rhs to window size
    my $rhs_len = length $line->{rhs};
    my $formatted_rhs = $line->{rhs};
    if ($rhs_len > $WINDOW_SIZE) {
        $formatted_rhs = substr($line->{rhs}, 0, $WINDOW_SIZE);
    }
    my $formatted_kwic_line =  {
        lhs => $formatted_lhs,
        keyword => $formatted_keyword,
        rhs => $formatted_rhs
    };
    # pad the fname if need be
    if ($FILENAMES || $BASENAMES) {
        my $formatted_fname = $line->{fname};
        my $fname_len = length $line->{fname};
        if ($fname_len < $MAX_FNAME_LEN) {
            $formatted_fname = $line->{fname} . (' ' x ($MAX_FNAME_LEN - $fname_len));
        }
        $formatted_kwic_line->{fname} = $formatted_fname;
    }
    return $formatted_kwic_line;
}
