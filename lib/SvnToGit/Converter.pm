#!/usr/bin/env perl

package SvnToGit::Converter;

=head1 NAME

SvnToGit::Converter - Convert a Subversion repository to Git

=head1 SYNOPSIS

  use SvnToGit::Converter;

  SvnToGit::Converter->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo",
    authors_file => "authors.txt"
  );

=cut

use Modern::Perl;
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use Cwd;
use Term::ANSIColor;
use IPC::Open3 () ;
use Symbol;
use Data::Dumper::Again;
use Data::Dumper::Simple;
my $dd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1);
my $tdd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1, terse => 1, indent => 0);

#use lib dirname(__FILE__) . "/..";

use SvnToGit::ConsistentLayoutConverter;
use SvnToGit::InconsistentLayoutConverter;

=head1 DESCRIPTION

SvnToGit::Converter is a class to encapsulate converting a Subversion
repository into a git repository. It makes system calls to git-svn to
do the bulk of the conversion, doing a little extra work to convert
the SVN way of doing things into the git way:

=over 4

=item *

git-svn maps SVN branches to git branches, but keeps them as remotes.
SvnToGit::Converter copies those to local branches so you can use them
right away.

=item *

git-svn maps Subversion tags to git branches. SvnToGit::Converter
creates real git tags instead.

=item *

git-svn will map trunk in your Subversion repo to an explicit branch,
and sometimes this is not the same as what ends up being master.
SvnToGit::Converter ensures that trunk maps correctly to master.

=back

Additionally, SvnToGit::Converter can handle the case in which the SVN
repo you're converting did not start out as having a conventional
trunk/branches/tags structure, but was moved over at a specific
revision in the history. Read L</"Converting a repo with an
inconsistent structure"> below for more information.

=head1 USAGE

If you want to quickly get started with SvnToGit::Converter, here are
a few use cases:

=head2 Converting a repo with a trunk/branches/tags structure

You don't have to do anything; this happens by default.

  SvnToGit::Converter->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo"
  );

=head2 Converting a part of a repo

Use the C<revisions> option. For instance, if you want the git repo
to contain only revisions 3-32 of the SVN repo:

  SvnToGit::Converter->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo"
    revisions => "3:32"
  );

=head2 Converting a repo with no trunk/branches/tags structure

Use the C<root_is_trunk> option.

  SvnToGit::Converter->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo"
    root_is_trunk => 1
  );

=head2 Converting a repo with an inconsistent structure

What do we mean by a repo with an inconsistent structure? Well, it's a
repo that didn't start out as having a conventional
trunk/branches/tags structure, but was moved over at a specific
revision in the history. For instance, maybe you originally created a
one-off project which took off, and halfway in you decided you needed
a branch. Unfortunately, if you were to convert such a project with
git-svn, you would lose some history as the repository you'd end up
with would stop at the point where trunk first came into existence.

This is where SvnToGit::Converter can help you. The way SvnToGit
converts such a repository is that the portion of the history up to
the revision in which trunk was introduced is copied to one
repository, and everything onward is copied as a second repository.
Then, the two repositories are stitched together in the end.

So, simply use the C<trunk_begins_at> option to tell the converter
where trunk was introduced:

  SvnToGit::Converter->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo",
    trunk_begins_at => 5,
  );

If it took a few revisions to move to the trunk/branches/tags layout
and you wish to remove some revisions from the final repository,
you can specify the C<root_is_trunk_until> option to specify an
endpoint for the first repository:

  SvnToGit::Converter->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo",
    root_is_trunk_until => 30
    trunk_begins_at => 33
  );

=head1 OPTIONS

SvnToGit::Converter takes all the options that its command-line
counterpart, L<svn2git>, takes. So read that for all the gory details.

=head1 METHODS

=head2 SvnToGit::Converter-E<gt>convert(%args)

Easy way to convert a repo all in one go. Simply passes the given
options to L<.new>, so read that for more.

=cut

sub convert {
  my($class, %args) = @_;
  my $c = $class->new(%args);
  $c->run;
  return $c;
}

=head2 SvnToGit::Converter-E<gt>new(%args)

Base method to create a new converter object.

L<SvnToGit::StandardLayoutConverter> and
L<SvnToGit::InconsistentLayoutConverter> extend this method, so see
them for more.

Receives the following options:

=over 4

=item B<trunk =E<gt> I<String>>

=item B<branches =E<gt> I<String>>

=item B<tags =E<gt> I<String>>

These tell the converter about the layout of your repository -- what
subdirectories contain the trunk, branches, and tags, respectively.

If none of these are specified, a standard Subversion layout is
assumed.

=item B<root_is_trunk =E<gt> I<Boolean>>

This tells the converter that trunk is at 'trunk', and not to worry
about the branches or tags (except for converting trunk to the master
branch).

=item B<clone =E<gt> I<Boolean>>

If false, skips the step of cloning the SVN repository. This is useful
when you just want to convert the tags on a git repository you'd
previously cloned using git-svn. Note that this assumes you're already
in the git repo.

True by default.

=item B<revision =E<gt> I<String>>, B<revisions =E<gt> I<String>>

Specifies which revision(s) within the Subversion repo show up in the
new git repo.

=item B<authors_file =E<gt> I<String>>

The location of the authors file to use when mapping Subversion authors
to git authors. See L<git-svn>'s C<-A> option for more on how this works.

=item B<strip_tag_prefix =E<gt> I<String>>

When converting tags, removes this string from each tag. For example,
C<--strip-tag-prefix="release-"> would turn "release-1.2.3" into
"1.2.3".

=item B<force =E<gt> I<Boolean>>

If the directory where the new git repo will be created already
exists, it will be overwritten.

=item B<verbosity_level =E<gt> I<Integer>>

If set to 0, nothing is output.

If set to 1 (the default), the active task will be printed to the
console.

If set to 2, the active task will be printed to the console, as well
as each shell command before it is executed.

If set to 3, the active task will be printed to the console, as well
as each shell command before it is executed and the output which that
command generates.

=back

=cut

sub new {
  my($class, %data) = @_;
  
  my $subclass = "SvnToGit::" . ($data{trunk_begins_at} ? 'InconsistentLayoutConverter' : 'ConsistentLayoutConverter');
  #eval "require $klass";
  $subclass->new(%data);
}

# Not documented.
# This is used by ->new and ConsistentLayoutConverter->new,
# so use that instead.
#
sub buildargs {
  my($class, %data) = @_;
  
  if (!$data{svn_repo}) {
    $class->bail("You must pass an svn_repo option!");
  }
  unless ($data{git_repo}) {
    $data{git_repo} = basename($data{svn_repo});
    if (-e $data{git_repo} && !$data{force}) {
      $data{git_repo} .= ".git";
    }
  }
  $data{git_repo} = rel2abs($data{git_repo});
  
  $data{verbosity_level} //= 1;
  
  return %data;
}

sub run {
  my $self = shift;
  $self->bail("Must be implemented");
}

sub create_git_repo_from_svn_repo {
  my($self, %args) = @_;
  
  my @keys = qw(svn_repo git_repo root_is_trunk trunk branches tags authors revision);
  $args{$_} //= $self->{$_} for @keys;
}

sub optimize_repo {
  my $self = shift;
  $self->git("gc");
  $self->git("repack", "-a", "-d", "-f", "--depth", "50", "--window", "50");
}

#---

sub default_authors_file {
  shift;
  "$ENV{HOME}/.svn2git/authors";
}

sub ensure_git_present {
  my $class = shift;
  `git --version`;
  die "git --version didn't work.  Is git installed?\n" if $?;
}

sub ensure_git_svn_present {
  my $self = shift;
  `git help svn`;
  die "git help svn didn't work.  Is git-svn installed?\n" if $?;
}

sub trunk_path {
  my $self = shift;
  $self->{trunk} || 'trunk';
}

sub branches_path {
  my $self = shift;
  $self->{branches} || 'branches';
}

sub tags_path {
  my $self = shift;
  $self->{tags} || 'tags';
}

sub get_branches_and_tags {
  my($self, $dir) = @_;
  
  my $oldcwd = $self->chdir($dir) if $dir;
  
  # Get the list of local and remote branches, taking care to ignore console color codes and ignoring the
  # '*' character used to indicate the currently selected branch.
  my @locals = map { s/^\*?\s+//; $_ } split("\n", `git branch -l --no-color`);
  my @remotes = map { s/^\*?\s+//; $_ } split("\n", `git branch -r --no-color`);
  
  my $local_branches = \@locals;
  # <-- TODO: local tags?
  
  my $remote_branches = [];
  my $remote_tags = [];
  for (@remotes) {
    # Tags are remote branches that (by default) start with "tags/".
    my $tags_path = $self->tags_path;
    my $branches = m{^$tags_path/} ? $remote_tags : $remote_branches;
    push @$branches, $_;
  }
  
  $self->chdir($oldcwd) if $dir;
  
  return {
    local_branches => $local_branches,
    remote_branches => $remote_branches,
    remote_tags => $remote_tags
  };
}

#---

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
    say colored(join(" ", @env, map { /[ ]/ ? $tdd->dump($_) : $_ } @cmd), "yellow");
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
  die "@cmd exited with $exit" if $exit;

  return @out;
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

sub git_svn {
  my($self, $subcommand, @args) = @_;
  
  #my $quiet_option = "";
  #given ($subcommand) {
  #  when("init")  { $quiet_option = undef }
  #  when("fetch") { $quiet_option = "-q" }
  #  default       { $quiet_option = "--quiet" }
  #}
  #unshift @args, $quiet_option if $quiet_option && $self->{verbosity_level} < 3;
  
  my @cmd = ("git", "svn", $subcommand, @args);
  
  $self->cmd(@cmd);
}

sub header {
  my($self, $msg) = @_;
  print "\n" . colored("##### $msg #####", "bold magenta") . "\n\n" if $self->{verbosity_level} > 0;
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

1;

__END__

=head1 DIFFERENCES FROM OTHER IMPLEMENTATIONS

=over 4

=item *

Updated fix_tags and fix_trunk so they're closer to Ruby script

=item *

Renamed C<--noclone> (as it is in the Perl script) to C<--no-clone>

=item *

Changed default behavior so that the directory for the git repo will be
auto-created for you. C<--no-clone> assumes you're already in the git
repo.

=item *

Added C<git_repo> option to allow user to customize new git repo location

=item *

Added C<--root-is-trunk> option (TODO: not present in Perl script?)

=item *

Added --revision option that will be passed to C<git svn fetch>

=item *

Added default authors file in F<~/.svn2git/authors>

=item *

Added a way to convert a SVN repo did not start out as having a
conventional trunk/branches/tags structure but was moved over at a
specific revision in the history.

=item *

Added --force option

=head1 AUTHOR

Elliot Winkler <elliot.winkler@gmail.com>

Greatly adapted from code by Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

=over 4

=item *

L<git-svn>

=item *

Michael Schwern's Perl script: L<http://github.com/schwern/svn2git>

=item *

Current fork of Ruby svn2git: L<http://github.com/nirvdrum/svn2git>

=back

=cut