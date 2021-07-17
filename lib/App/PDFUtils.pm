package App::PDFUtils;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Perinci::Object;

our %SPEC;

my %argspec0_files = (
    files => {
        schema => ['array*', of=>'filename*', min_len=>1,
                   #uniq=>1, # not yet implemented by Data::Sah
               ],
        req => 1,
        pos => 0,
        slurpy => 1,
        'x.element_completion' => [filename => {filter => sub { /\.pdf$/i }}],
    },
);

our %argspec0_file = (
    file => {
        summary => 'Input file',
        schema => ['filename*'],
        req => 1,
        pos => 0,
        'x.completion' => [filename => {filter => sub { /\.pdf$/i }}],
    },
);

our %argspecopt1_output = (
    output => {
        summary => 'Output path',
        schema => ['filename*'],
        pos => 1,
    },
);

our %argspecopt_overwrite = (
    overwrite => {
        schema => 'bool*',
        cmdline_aliases => {O=>{}},
    },
);

our %argspecopt_return_output_file = (
    return_output_file => {
        summary => 'Return the path of output file instead',
        schema => 'bool*',
        description => <<'_',

This is useful when you do not specify an output file but do not want to show
the converted document to stdout, but instead want to get the path to a
temporary output file.

_
    },
);

$SPEC{add_pdf_password} = {
    v => 1.1,
    summary => 'Password-protect PDF files',
    description => <<'_',

This program is a wrapper for <prog:qpdf> to password-protect PDF files
(in-place). This is the counterpart for <prog:remove-pdf-password>.

_
    args => {
        %argspec0_files,
        password => {
            schema => ['str*', min_len=>1],
            req => 1,
        },
        backup => {
            summary => 'Whether to backup the original file to ORIG~',
            schema => 'bool*',
            default => 1,
        },
        # XXX key_length (see qpdf, but when 256 can't be opened by evince)
        # XXX other options (see qpdf)
    },
    deps => {
        prog => 'qpdf',
    },
    links => [
        {url => 'prog:remove-pdf-password'},
    ],
};
sub add_pdf_password {
    #require File::Temp;
    require IPC::System::Options;
    #require Proc::ChildError;
    #require Path::Tiny;

    my %args = @_;

    my $envres = envresmulti();

  FILE:
    for my $f (@{ $args{files} }) {
        unless (-f $f) {
            $envres->add_result(404, "File not found", {item_id=>$f});
            next FILE;
        }
        # XXX test that tempfile doesn't yet exist. but actually we can't avoid
        # race condition because qpdf is another process
        my $tempf = "$f.tmp" . int(rand()*900_000 + 100_000);

        my $decrypted;
        my ($stdout, $stderr);
        IPC::System::Options::system(
            {log => 1, capture_stdout => \$stdout, capture_stderr => \$stderr},
            "qpdf", "--encrypt", $args{password}, $args{password}, 128, "--", $f, $tempf);
        my $err = $?;# ? Proc::ChildError::explain_child_error() : '';
        if ($err && $stderr =~ /: invalid password$/) {
            $envres->add_result(412, "File already encrypted", {item_id=>$f});
            next FILE;
        } elsif ($err) {
            $stderr =~ s/\R//g;
            $envres->add_result(500, $stderr, {item_id=>$f});
            next FILE;
        }

      BACKUP:
        {
            last unless $args{backup};
            unless (rename $f, "$f~") {
                warn "Can't backup original '$f' to '$f~': $!, skipped backup\n";
                last;
            };
        }
        unless (rename $tempf, $f) {
            $envres->add_result(500, "Can't rename $tempf to $f: $!", {item_id=>$f});
            next FILE;
        }
        $envres->add_result(200, "OK", {item_id=>$f});
    }

    $envres->as_struct;
}

$SPEC{remove_pdf_password} = {
    v => 1.1,
    summary => 'Remove password from PDF files',
    description => <<'_',

This program is a wrapper for <prog:qpdf> to remove passwords from PDF files
(in-place).

The motivation for this program is the increasing occurence of financial
institutions sending financial statements or documents in the format of
password-protected PDF file. This is annoying when we want to archive the file
or use it in an organization because we have to remember different passwords for
different financial institutions and re-enter the password everytime we want to
use the file. (The banks could've sent the PDF in a password-protected .zip, or
use PGP-encrypted email, but I digress.)

You can provide the passwords to be tried in a configuration file,
`~/remove-pdf-password.conf`, e.g.:

    passwords = pass1
    passwords = pass2
    passwords = pass3

or:

    passwords = ["pass1", "pass2", "pass3"]

_
    args => {
        %argspec0_files,
        passwords => {
            schema => ['array*', of=>['str*', min_len=>1], min_len=>1],
        },
        backup => {
            summary => 'Whether to backup the original file to ORIG~',
            schema => 'bool*',
            default => 1,
        },
    },
    deps => {
        prog => 'qpdf',
    },
    links => [
        {url => 'prog:add-pdf-password'},
    ],
};
sub remove_pdf_password {
    #require File::Temp;
    require IPC::System::Options;
    #require Proc::ChildError;
    #require Path::Tiny;

    my %args = @_;

    my $envres = envresmulti();

  FILE:
    for my $f (@{ $args{files} }) {
        unless (-f $f) {
            $envres->add_result(404, "File not found", {item_id=>$f});
            next FILE;
        }
        # XXX test that tempfile doesn't yet exist. but actually we can't avoid
        # race condition because qpdf is another process
        my $tempf = "$f.tmp" . int(rand()*900_000 + 100_000);

        my $decrypted;
      PASSWORD:
        for my $p (@{ $args{passwords} }) {
            my ($stdout, $stderr);
            IPC::System::Options::system(
                {log => 1, fail_log_level => 'info', capture_stdout => \$stdout, capture_stderr => \$stderr},
                "qpdf", "--password=$p", "--decrypt", $f, $tempf);
            my $err = $?;# ? Proc::ChildError::explain_child_error() : '';
            if ($err && $stderr =~ /: invalid password$/) {
                #$log->tracef("D1");
                unlink $tempf; # just to make sure
                next PASSWORD;
            } elsif ($err) {
                #$log->tracef("D2");
                $stderr =~ s/\R//g;
                $envres->add_result(500, $stderr, {item_id=>$f});
                next FILE;
            }
            last;
        }
        unless (-f $tempf) {
            $envres->add_result(412, "No passwords can be successfully used on $f", {item_id=>$f});
            next FILE;
        }

      BACKUP:
        {
            last unless $args{backup};
            unless (rename $f, "$f~") {
                warn "Can't backup original '$f' to '$f~': $!, skipped backup\n";
                last;
            };
        }
        unless (rename $tempf, $f) {
            $envres->add_result(500, "Can't rename $tempf to $f: $!", {item_id=>$f});
            next FILE;
        }
        $envres->add_result(200, "OK", {item_id=>$f});
    }

    $envres->as_struct;
}

$SPEC{convert_pdf_to_text} = {
    v => 1.1,
    summary => 'Convert PDF file to text',
    description => <<'_',

This utility uses one of the following backends:

* pdftotext

_
    args => {
        %argspec0_file,
        %argspecopt1_output,
        %argspecopt_overwrite,
        %argspecopt_return_output_file,
        pages => {
            summary => 'Only convert a range of pages',
            schema => 'uint_range*',
        },
        fmt => {
            summary => 'Run Unix fmt over the txt output',
            schema => 'bool*',
        },
    },
};
sub convert_pdf_to_text {
    my %args = @_;

    require File::Copy;
    require File::Temp;
    require File::Temp::MoreUtils;
    require File::Which;
    require IPC::System::Options;

  USE_PDFTOTEXT: {
        File::Which::which("pdftotext") or do {
            log_debug "pdftotext is not in PATH, skipped trying to use pdftotext";
            last;
        };

        my $input_file = $args{file};
        $input_file =~ /(.+)\.(\w+)\z/ or return [412, "Please supply input file with extension in its name (e.g. foo.pdf instead of foo)"];
        my ($name, $ext) = ($1, $2);
        $ext =~ /\Ate?xt\z/i and return [304, "Input file '$input_file' is already text"];
        my $output_file = $args{output};

        if (defined $output_file && -e $output_file && !$args{overwrite}) {
            return [412, "Output file '$output_file' already exists, not overwriting (use --overwrite (-O) to overwrite)"];
        }

        my $tempdir = File::Temp::tempdir(CLEANUP => !$args{return_output_file});
        my ($temp_fh, $temp_file)      = File::Temp::MoreUtils::tempfile_named(name=>$input_file, dir=>$tempdir);
        (my $temp_out_file = $temp_file) =~ s/\.\w+\z/.txt/;

        if (defined $args{pages}) {
            File::Which::which("pdftk")
                  or return [412, "pdftk is required to extract page range from PDF"];
            IPC::System::Options::system(
                {die=>1, log=>1},
                "pdftk", $input_file, "cat", $args{pages}, "output", $temp_file);
        } else {
            File::Copy::copy($input_file, $temp_file) or do {
                return [500, "Can't copy '$input_file' to '$temp_file': $!"];
            };
        }

      EXTRACT_PAGE_RANGE: {
            last unless defined $args{pages};

        }

        IPC::System::Options::system(
            {die=>1, log=>1},
            "pdftotext", $temp_file, $temp_out_file);

      FMT: {
            last unless $args{fmt};
            return [412, "fmt is not in PATH"] unless File::Which::which("fmt");
            my $stdout;
            IPC::System::Options::system(
                {die=>1, log=>1, capture_stdout=>\$stdout},
                "fmt", $temp_out_file,
            );
            open my $fh, ">" , "$temp_out_file.fmt" or return [500, "Can't open '$temp_out_file.fmt': $!"];
            print $fh $stdout;
            close $fh;
            $temp_out_file .= ".fmt";
        }

        if (defined $output_file || $args{return_output_file}) {
            if (defined $output_file) {
                File::Copy::copy($temp_out_file, $output_file) or do {
                    return [500, "Can't copy '$temp_out_file' to '$output_file': $!"];
                };
            } else {
                $output_file = $temp_out_file;
            }
            return [200, "OK", $args{return_output_file} ? $output_file : undef];
        } else {
            open my $fh, "<", $temp_out_file or return [500, "Can't open '$temp_out_file': $!"];
            local $/;
            my $content = <$fh>;
            close $fh;
            return [200, "OK", $content, {"cmdline.skip_format"=>1}];
        }
    }

    [412, "No backend available"];
}

1;
# ABSTRACT: Command-line utilities related to PDF files

=head1 SYNOPSIS

This distribution provides tha following command-line utilities related to PDF
files:

#INSERT_EXECS_LIST


=head1 SEE ALSO

L<diff-pdf-text> from L<App::DiffPDFText>.

=cut
