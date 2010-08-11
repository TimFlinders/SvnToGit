#!/usr/bin/env perl

=head1 NAME

svn2git - Convert a Subversion repository to Git

=head1 SYNOPSIS

B<svn2git setup [OPTIONS] REMOTE_SVN_REPO_URL LOCAL_SVN_REPO_DIR>

B<svn2git convert [OPTIONS] SVN_REPO_URL [FINAL_GIT_REPO_DIR]>

Run C<--help> for the list of options.

=cut

package SvnToGit::Cli;

use Modern::Perl;
use Getopt::Long qw(GetOptionsFromArray);
use Pod::Usage;
use Pod::Find qw(pod_where);
use Term::ANSIColor;
use Cwd;
use IPC::Open3 () ;
use Symbol;
use File::Basename;
use Data::Dumper::Again;
use Data::Dumper::Simple;
my $dd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1);
my $tdd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1, terse => 1, indent => 0);

use SvnToGit::Converter;

my @DEFAULT_OPTIONS = (
  "really-verbose|vv",
  "verbose|v",
  "quiet|q",
  "help|h"
);

sub run {
  my($class_or_self, @args) = @_;
  if (ref $class_or_self eq "SvnToGit::Cli") {
    # instance method
    my $subcommand = shift @{$class_or_self->{args}};
    Getopt::Long::Configure("pass_through");
    $class_or_self->getopts;
    Getopt::Long::Configure("no_pass_through");
    given ($subcommand) {
      when ("setup") {
        $class_or_self->setup;
      }
      when ("convert") {
        $class_or_self->convert;
      }
      default {
        $class_or_self->exit_with_usage(2);
      }
    }
  }
  else {
    # class method
    $class_or_self->new(@args)->run;
  }
}

sub new {
  my($klass, @args) = @_;  
  my $self = { args => \@args, opts => {} };
  bless($self, $klass);
}

sub exit_with_usage {
  my($self, $exitval) = @_;
  print "\n";
  pod2usage(-exitval => $exitval, -input => pod_where({-inc => 1}, __PACKAGE__));
}

sub getopts {
  my($self, @custom_options) = @_;  
  GetOptionsFromArray(
    $self->{args},
    $self->{opts},
    @DEFAULT_OPTIONS,
    @custom_options
  ) or $self->exit_with_usage(2);
  $self->exit_with_usage(1) if $self->{opts}->{help};
  
  $self->clean_opts;
  
  $self->{verbosity_level} = $self->{opts}->{verbosity_level};
}

sub clean_opts {
  my $self = shift;
  
  my $o = $self->{opts};
  
  # convert --foo-bar to $args{foo_bar}
  for my $k (keys %{$o}) {
    my $v = $o->{$k};
    (my $nk = $k) =~ s/-/_/g;
    delete $o->{$k};
    $o->{$nk} = $v;
  }
  
  if ($o->{quiet}) {
    $o->{verbosity_level} = 0;
  } elsif ($o->{verbose}) {
    $o->{verbosity_level} = 2;
  } elsif ($o->{really_verbose}) {
    $o->{verbosity_level} = 3;
  }
  $o->{verbosity_level} //= 1;
}

sub setup {
  my $self = shift;
  
  # We've already parsed command line options,
  # but unknown options may have slipped through
  # so let's do it more strictly this time.
  $self->getopts;
  
  $self->exit_with_usage(2) if @{$self->{args}} < 2;
  my($remote_svn_repo, $local_svn_repo) = @{$self->{args}};
  
  $remote_svn_repo =~ m{(\w+)://};
  if (!$1) {
    $self->bail("Remote SVN repo must be a URL.")
  } elsif ($1 eq "file") {
    print <<EOT;
It looks like the SVN repo you've specified points to a local directory.
Since 'setup' is intended to copy a repo on a remote server, you can
just go ahead and convert the repo you have locally.
EOT
    return;
  }
  
  $self->info("Making a local copy of the SVN repo...");
  if ($local_svn_repo !~ m{(\w+)://}) {
    # ok, must be a file.
    if (-e $local_svn_repo) {
      # provide an option for this?
      $self->cmd("rm", "-rf", $local_svn_repo)
    }
    $self->cmd("svnadmin", "create", $local_svn_repo);
    $self->command("echo '#!/bin/sh' >> $local_svn_repo/hooks/pre-revprop-change");
    $self->command("chmod 0755 $local_svn_repo/hooks/pre-revprop-change");
    # http://journal.paul.querna.org/articles/2006/09/14/using-svnsync/
    open my $ofh, ">", "$local_svn_repo/hooks/pre-revprop-change" or die "Couldn't open file for writing: $!";
    say $ofh "#!/bin/sh";
    close $ofh;
    chmod 0755, "$local_svn_repo/hooks/pre-revprop-change" or die "Couldn't chmod file: $!";
    $local_svn_repo = "file://$local_svn_repo";
  }
  $self->cmd("svnsync", "init", "--non-interactive", "-q", $local_svn_repo, $remote_svn_repo);
  $self->cmd("svnsync", "sync", "--non-interactive", "-q", $local_svn_repo);
}

sub convert {
  my $self = shift;
  
  $self->getopts(
    "trunk:s", "branches:s", "tags:s", "root-only",
    "authors-file|A:s",
    "clone!",
    "strip-tag-prefix:s",
    "revision|r:s",
    "grafts-file=s",
    "end-root-only-at=i",
    "start-std-layout-at=i",
    "clear-cache",
    "force|f"
  );
  
  $self->exit_with_usage(2) if @{$self->{args}} < 2;
  my($svn_repo, $git_repo) = @{$self->{args}};
  $self->{opts}->{svn_repo} = $svn_repo;
  $self->{opts}->{git_repo} = $git_repo;
  
  SvnToGit::Converter->convert( %{$self->{opts}} );
}

sub chdir {
  my($self, $dir) = @_;
  my $oldcwd = getcwd();
  chdir $dir or die "Couldn't chdir: $!";
  my $cwd = getcwd();
  $self->debug("Current directory: $cwd");
  $oldcwd;
}

sub cmd {
  my($self, @cmd) = @_;
  
  my $opts = (ref $cmd[-1] eq "HASH") ? pop @cmd : {};
  my %OLDENV = ();
  
  #if (ref $cmd[-1] eq "HASH") {
  #  my $env = pop @cmd;
  #  my @tmp = ();
  #  while (my($k,$v) = each %$env) {
  #    push @tmp, "$k=\"$v\"";
  #  }
  #  my $pre = join(" ", @tmp);
  #  $cmd[0] = $pre . " " . $cmd[0];
  #}
  
  for my $k (keys %{$opts->{env}}) {
    $OLDENV{$k} = $ENV{$k};
    $ENV{$k} = $opts->{env}->{$k};
  }
  
  if ($self->{verbosity_level} >= 2) {
    my @env = map { join "=", $_, $tdd->dump($opts->{env}->{$_}) } keys %{$opts->{env}};
    $self->command( join(" ", @env, map { /[ ]/ ? $tdd->dump($_) : $_ } @cmd) );
  }
  
  # Stolen from Git::Wrapper
  my (@out, @err, $wtr, $rdr, $err);
  $err = Symbol::gensym;
  my $pid = IPC::Open3::open3($wtr, $rdr, $err, @cmd);
  close $wtr;
  while (defined(my $x = <$rdr>) | defined(my $y = <$err>)) {
    if (defined $x) {
      chomp $x;
      say $x if $self->{verbosity_level} >= 3;
      push @out, $x;
    }
    if (defined $y) {
      chomp $y;
      say $y if $self->{verbosity_level} >= 3;
      push @err, $y;
    }
  }
  waitpid $pid, 0;
  
  for my $k (keys %OLDENV) {
    $ENV{$k} = $OLDENV{$k};
  }

  my $exit = $? >> 8;
  if ($exit) {
    say join("\n", @err);
    die "@cmd exited with $exit";
  }

  return @out;
}

sub command {
  my($self, $msg) = @_;
  say colored($msg, "yellow") if $self->{verbosity_level} >= 2;
}

sub git {
  my($self, $subcommand, @args) = @_;
  
  #my $quiet_option = "";
  #given ($subcommand) {
  #  when("tag")  { $quiet_option = undef }
  #  #when("fetch") { $quiet_option = "-q" }
  #  default       { $quiet_option = "--quiet" }
  #}
  #unshift @args, $quiet_option if $quiet_option && $self->{verbosity_level} < 3;
  
  my @cmd = ("git", $subcommand, @args);
  
  $self->cmd(@cmd);
}

sub header {
  my($self, $msg) = @_;
  say "\n" . colored($msg, "bold magenta") if $self->{verbosity_level} > 0;
}

sub info {
  my($self, $msg) = @_;
  say colored($msg, "green") if $self->{verbosity_level} > 0;
}

sub debug {
  my($self, $msg) = @_;
  say colored($msg, "bold black") if $self->{verbosity_level} >= 3;
}

sub strip {
  my($self, $str) = @_;
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  return $str;
}

sub bail {
  my ($self, @args) = @_;
  die "SvnToGit::Converter: @args\n";
}

__END__

=head1 DESCRIPTION

svn2git converts a Subversion repository into a git repository. It
uses git-svn to do the bulk of the conversion, but does a little extra
work to convert the SVN way of doing things into the git way.

Specifically, svn2git can be useful in the case where the SVN repo
you're converting did not start out as having a conventional
trunk/branches/tags structure, but was moved over at a specific
revision in the history.

More documentation is available in L<SvnToGit::Converter>, so please
read that for more.

=head1 OPTIONS

As you probably noticed in the SYNOPSIS, there are two ways of calling
this script:

  svn2git setup ...
  svn2git convert ...

=head2 Options for C<svn2git setup>

Nothing but the default options, so see below for more.

=head2 Options for C<svn2git convert>

=over 4

=item B<--trunk TRUNK_PATH>

=item B<--branches BRANCHES_PATH>

=item B<--tags TAGS_PATH>

These tell the converter about the layout of your repository -- what
subdirectories contain the trunk, branches, and tags, respectively.

If none of these are specified, a standard trunk/branches/tags layout
is assumed.

=item B<--root-only>

This tells the converter that you never had a conventional
trunk/branches/tags layout in your repository, and you just want
whatever's in the root folder to show up as the master branch.

=item B<--no-clone>

Skips the step of cloning the SVN repository. This is useful
when you just want to convert the tags on a git repository you'd
previously cloned using git-svn. Note that this assumes you're already
in the git repo.

=item B<--revision REV>, B<-r REV>

=item B<--revision REV1:REV2>, B<-r REV1:REV2>

Specifies which revision(s) within the Subversion repo show up in the
new git repo.

=item B<--authors-file AUTHORS_FILE>

The location of the authors file to use when mapping Subversion authors
to git authors. See L<git-svn>'s C<-A> option for more on how this works.

=item B<--strip-tag-prefix>

When converting tags, removes this string from each tag. For example,
C<--strip-tag-prefix="release-"> would turn "release-1.2.3" into
"1.2.3".

=item B<--force>, B<-f>

If the directory where the new git repo will be created already
exists, it will be overwritten.

=head2 Common options

=item B<--verbose>, B<-v>

Each shell command will be printed to the console before it is
executed.

=item B<--really-verbose>, B<-vv>

Each shell command will be printed to the console before it is
executed, as well as the output which that command generates.

=item B<--quiet>, B<-q>

Prevents anything from being printed to the console.

=back

=head1 EXAMPLES

Convert an SVN project with a standard structure, autocreating the
F<some-project> directory:

  svn2git http://svn.example.com/some-project

Convert an SVN project that doesn't have a trunk/branches/tags
structure:

  svn2git http://svn.example.com/some-project --root-is-trunk

Convert an SVN project into the F<some-dir> directory:

  svn2git http://svn.example.com/some-project some-dir

Perform tag and trunk mapping on an existing git repo you've created
using git-svn:

  cd some-git-svn-project
  svn2git --no-clone

=head1 AUTHOR

Elliot Winkler <elliot.winkler@gmail.com>

Greatly adapted from code by Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

=over 4

=item *

L<SvnToGit>

=item *

L<git-svn>

=item *

Michael Schwern's Perl script: L<http://github.com/schwern/svn2git>

=item *

Current fork of Ruby svn2git: L<http://github.com/nirvdrum/svn2git>

=back

=cut