## no critic: InputOutput::RequireBriefOpen

package App::pdfgrep;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use AppBase::Grep;
use IPC::System::Options qw(system);
use Perinci::Sub::Util qw(gen_modified_sub);

our %SPEC;

gen_modified_sub(
    output_name => 'pdfgrep',
    base_name   => 'AppBase::Grep::grep',
    summary     => 'Print lines matching text in PDF files',
    description => <<'_',

This is a wrapper for pdftotext + grep-like utility that is based on
<pm:AppBase::Grep>. The unique features include multiple patterns and
`--dash-prefix-inverts`.

_
    add_args    => {
        files => {
            description => <<'_',

If not specified, will search for all PDF files recursively from the current
directory.

_
            'x.name.is_plural' => 1,
            'x.name.singular' => 'file',
            schema => ['array*', of=>'filename*'],
            pos => 1,
            slurpy => 1,
        },
        # XXX recursive (-r)
    },
    modify_meta => sub {
        my $meta = shift;
        $meta->{examples} = [
        ];
        $meta->{links} = [
        ];
        $meta->{deps} = {
            prog => 'pdftotext',
        };
    },
    output_code => sub {
        my %args = @_;
        my ($tempdir, $fh, $file);

        my @files = @{ $args{files} // [] };
        if ($args{regexps} && @{ $args{regexps} }) {
            unshift @files, delete $args{pattern};
        }
        unless (@files) {
            require File::Find::Rule;
            @files = File::Find::Rule->new->file->name("*.pdf", "*.PDF")->in(".");
            unless (@files) { return [200, "No PDF files to search against"] }
        }

        my $show_label = @files > 1 ? 1:0;

        $args{_source} = sub {
          READ_LINE:
            {
                if (!defined $fh) {
                    return unless @files;

                    unless (defined $tempdir) {
                        require File::Temp;
                        $tempdir = File::Temp::tempdir(CLEANUP=>$ENV{DEBUG} ? 0:1);
                    }

                    $file = shift @files;
                    require File::Basename;
                    my $tempfile = File::Basename::basename($file) . ".txt";
                    my $i = 0;
                    while (1) {
                        my $tempfile2 = $tempfile . ($i ? ".$i" : "");
                        do { $tempfile = $tempfile2; last } unless -e "$tempdir/$tempfile2";
                        $i++;
                    }

                    log_trace "Running pdftotext $file $tempdir/$tempfile ...";
                    system "pdftotext", $file, "$tempdir/$tempfile"; # XXX check error

                    open $fh, "<", "$tempdir/$tempfile" or do {
                        warn "pdfgrep: Can't open '$tempdir/$tempfile': $!, skipped\n";
                        undef $fh;
                    };
                    redo READ_LINE;
                }

                my $line = <$fh>;
                if (defined $line) {
                    return ($line, $show_label ? $file : undef);
                } else {
                    undef $fh;
                    redo READ_LINE;
                }
            }
        };

        AppBase::Grep::grep(%args);
    },
);

1;
# ABSTRACT:
