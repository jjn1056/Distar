package Distar;

use strictures 1;
use base qw(Exporter);

use Config;
use File::Spec;

use ExtUtils::MakeMaker 6.57_10 ();

our $VERSION = '0.001000';
$VERSION = eval $VERSION;

our @EXPORT = qw(
  author repository bugtracker irc manifest_include run_preflight
);

sub import {
  strictures->import;
  shift->export_to_level(1,@_);
}

sub author { our $Author = shift }
sub repository { our $Repository = shift }
sub bugtracker { our $Bugtracker = shift }
sub irc { our $IRC = shift }

our $Ran_Preflight;

our @Manifest = (
  'lib' => '.pm',
  't' => '.t',
  't/lib' => '.pm',
  'xt' => '.t',
  'xt/lib' => '.pm',
  '' => qr{[^/]*\.PL},
  '' => qr{Changes|MANIFEST|README|META\.yml},
  'maint' => qr{[^.].*},
);

sub manifest_include {
  push @Manifest, @_;
}

sub write_manifest_skip {
  use autodie;
  my @files = @Manifest;
  my @parts;
  while (my ($dir, $spec) = splice(@files, 0, 2)) {
    my $re = ($dir ? $dir.'/' : '').
      ((ref($spec) eq 'Regexp')
        ? $spec
        : !ref($spec)
          ? ".*\Q${spec}\E"
            # print ref as well as stringification in case of overload ""
          : die "spec must be string or regexp, was: ${spec} (${\ref $spec})");
    push @parts, $re;
  }
  my $final = '^(?!'.join('|', map "${_}\$", @parts).')';
  open my $skip, '>', 'MANIFEST.SKIP';
  print $skip "${final}\n";
  close $skip;
}

sub run_preflight {
  $Ran_Preflight = 1;

  system("git fetch");

  my $make = $Config{make};
  my $null = File::Spec->devnull;

  for (scalar `"$make" manifest 2>&1 >$null`) {
    $_ && die "$make manifest changed:\n$_ Go check it and retry";
  }

  for (scalar `git status`) {
    /^# On branch master/ || die "Not on master. EEEK";
    /Your branch is behind|Your branch and .*? have diverged/ && die "Not synced with upstream";
  }

  for (scalar `git diff`) {
    length && die "Outstanding changes";
  }
  my $ymd = sprintf(
    "%i-%02i-%02i", (localtime)[5]+1900, (localtime)[4]+1, (localtime)[3]
  );
  my @cached = grep /^\+/, `git diff --cached -U0`;
  @cached > 0 or die "Please add:\n\n$ARGV[0] - $ymd\n\nto Changes stage Changes (git add Changes)";
  @cached == 2 or die "Pre-commit Changes not just Changes line";
  $cached[0] =~ /^\+\+\+ .\/Changes\n/ or die "Changes not changed";
  $cached[1] eq "+$ARGV[0] - $ymd\n" or die "Changes new line should be: \n\n$ARGV[0] - $ymd\n ";
}

sub MY::postamble {
    my $post = <<'END';
preflight:
	perl -IDistar/lib -MDistar -erun_preflight $(VERSION)
release: preflight
	$(MAKE) disttest
	rm -rf $(DISTVNAME)
	$(MAKE) $(DISTVNAME).tar$(SUFFIX)
	git commit -a -m "Release commit for $(VERSION)"
	git tag v$(VERSION) -m "release v$(VERSION)"
	cpan-upload $(DISTVNAME).tar$(SUFFIX)
	git push origin --tags HEAD
distdir: readmefile
readmefile: create_distdir
	pod2text $(VERSION_FROM) >$(DISTVNAME)/README
	$(NOECHO) cd $(DISTVNAME) && $(ABSPERLRUN) ../Distar/helpers/add-readme-to-manifest
END
    if (open my $fh, '<', 'maint/Makefile.include') {
        $post .= do { local $/; <$fh> };
    }
    return $post;
}

{
  no warnings 'redefine';
  sub main::WriteMakefile {
    my %args = @_;
    if (!exists $args{VERSION_FROM}) {
      my $main = $args{NAME};
      $main =~ s{-|::}{/}g;
      $main = "lib/$main.pm";
      if (-e $main) {
        $args{VERSION_FROM} = $main;
      }
    }
    $args{LICENSE} ||= 'perl';

    if (-d 'xt') {
      push @{$args{META_MERGE}{no_index}{directory}||=[]}, 'xt';
    }

    my %meta_add = %{$args{META_ADD}||{}};
    $meta_add{'meta-spec'}{'version'} = 2;
    $meta_add{prereqs}{configure}{requires} = \%{$args{CONFIGURE_REQUIRES}||{}};
    $meta_add{prereqs}{build}{requires} = \%{$args{BUILD_REQUIRES}||{}};
    $meta_add{prereqs}{test}{requires} = \%{$args{TEST_REQUIRES}||{}};
    $meta_add{prereqs}{runtime}{requires} = \%{$args{PREREQ_PM}||{}};
    if ($args{MIN_PERL_VERSION}) {
      $meta_add{prereqs}{runtime}{requires}{perl} = $args{MIN_PERL_VERSION};
    }
    if (our $Repository) {
      $meta_add{resources}{repository} = ref $Repository ? $Repository : do {
        if ($Repository =~ m{^\w+://github\.com/(.*?)(?:\.git)?$}) {
          {
            url => "git://github.com/$1.git",
            web => "http://github.com/$1",
            type => 'git',
          };
        }
        elsif ($Repository =~ m{^\w+://git\.shadowcat\.co\.uk/(.*?)(?:\.git)?$}) {
          {
            url => "git://git.shadowcat.co.uk/$1.git",
            web => "http://git.shadowcat.co.uk/gitweb/gitweb.cgi?p=$1.git",
            type => 'git',
          };
        }
        else {
          {
            url => $Repository,
          };
        }
      };
    }
    if (our $IRC) {
      $meta_add{resources}{x_IRC} = $IRC;
    }
    if (our $Bugtracker) {
      $meta_add{resources}{bugtracker} = ref $Bugtracker ? $Bugtracker : do {
        if (lc $Bugtracker eq 'rt') {
          my $name = $args{NAME};
          $name =~ s/::/-/g;
          {
            web => "http://rt.cpan.org/NoAuth/Bugs.html?Dist=$name",
            mailto => 'bug-'.lc $name.'@rt.cpan.org',
          };
        }
        elsif ($Bugtracker =~ /^mailto:(.*)/) {
          { mailto => $1 };
        }
        else {
          { web => $Bugtracker };
        }
      };
    }
    if ($args{LICENSE} eq 'perl') {
      $meta_add{resources}{license} ||= [ 'http://dev.perl.org/licenses/' ];
    }
    $args{META_ADD} = \%meta_add;
    if ($args{META_MERGE}) {
      $args{META_MERGE}{'meta-spec'}{'version'} = 2;
    }
    ExtUtils::MakeMaker::WriteMakefile(
      %args,
      AUTHOR => our $Author,
      ABSTRACT_FROM => $args{VERSION_FROM},
      test => { TESTS => ($args{test}{TESTS}||'t/*.t').' xt/*.t' },
    );
  }
}

END {
  write_manifest_skip() unless $Ran_Preflight
}

1;
