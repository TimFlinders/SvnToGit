#!/usr/bin/env perl
#
# svn2git - A reimplementation of James Coglan's svn2git Ruby script
# as a Perl module and accompanying executable, adapted from
# http://github.com/schwern/svn2git by Elliot Winkler.
#

=head1 NAME

SvnToGit - Convert a Subversion repository to Git

=head1 SYNOPSIS

  use SvnToGit;

  SvnToGit->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo",
    authors_file => "authors.txt"
  );

=head1 DESCRIPTION

SvnToGit is a class to encapsulate converting a Subversion repository
into a git repository. It makes system calls to git-svn to do the bulk
of the conversion, doing a little extra work to convert the SVN way of
doing things into the git way:

=over 4

=item *

git-svn maps SVN branches to git branches, but keeps them as remotes.
SvnToGit copies those to local branches so you can use them right
away.

=item *

git-svn maps Subversion tags to git branches. SvnToGit creates real
git tags instead.

=item *

git-svn will map trunk in your Subversion repo to an explicit branch,
and sometimes this is not the same as what ends up being master.
SvnToGit ensures that trunk maps correctly to master.

=back

Additionally, SvnToGit can handle the case in which the SVN repo
you're converting did not start out as having a conventional
trunk/branches/tags structure, but was moved over at a specific
revision in the history. Read L</"Converting a repo with an
inconsistent structure"> below for more information.

=head1 USAGE

If you want to quickly get started with SvnToGit, here are a few use cases:

=head2 Converting a repo with a trunk/branches/tags structure

You don't have to do anything; this happens by default.

  SvnToGit->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo"
  );

=head2 Converting a part of a repo

Use the C<revisions> option. For instance, if you want the git repo
to contain only revisions 3-32 of the SVN repo:

  SvnToGit->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo"
    revisions => "3:32"
  );

=head2 Converting a repo with no trunk/branches/tags structure

Use the C<root_is_trunk> option.

  SvnToGit->convert(
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

This is where SvnToGit can help you. The way SvnToGit converts such a
repository is that the portion of the history up to the revision in
which trunk was introduced is copied to one repository, and everything
onward is copied as a second repository. Then, the two repositories
are stitched together in the end.

So, simply use the C<trunk_begins_at> option to tell the converter
where trunk was introduced:

  SvnToGit->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo",
    trunk_begins_at => 5,
  );

If it took a few revisions to move to the trunk/branches/tags layout
and you wish to remove some revisions from the final repository,
you can specify the C<root_is_trunk_until> option to specify an
endpoint for the first repository:

  SvnToGit->convert(
    svn_repo => "svn://your/svn/repo",
    git_repo => "/path/to/new/git/repo",
    root_is_trunk_until => 30
    trunk_begins_at => 33
  );

=head1 OPTIONS

SvnToGit takes all the options that its command-line counterpart,
L<svn2git>, takes. So read that for all the gory details.

=head1 METHODS

=cut

package SvnToGit;

# don't know if this should be above package or below
use Modern::Perl;
use File::Basename;

our $DEFAULT_AUTHORS_FILE = "$ENV{HOME}/.svn2git/authors";

#---

=head2 SvnToGit.convert(%args)

Easy way to convert a repo all in one go. Simply passes the given
options to L<.new>, so read that for more.

=cut

sub convert {
  my($class, %args) = @_;
  my $c = $class->new(%args);
  $c->run;
  return $c;
}

=head2 SvnToGit.new(%args)

Creates a new converter object.

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

If set to 1, prints each shell command executed.

If set to 2, outputs each shell command executed, as well as the output which that
command generates.

Defaults to 0.

=back

=cut

sub new {
  my($class, %args) = @_;
  unless ($args{git_repo}) {
    $args{git_repo} = basename($args{svn_repo});
    if (-e $args{git_repo}) {
      $args{git_repo} .= ".git";
    }
  }
  $args{revision} = $args{revisions} if $args{revisions};
  $args{authors} = $args{authors_file} if $args{authors_file};
  $args{clone} = 1 unless exists $args{clone};
  if (-f $DEFAULT_AUTHORS_FILE && !$args{authors}) {
    $args{authors} = $DEFAULT_AUTHORS_FILE;
  }
  if ($args{authors} && ! -f $args{authors}) {
    die "The authors file you specified doesn't exist.\n"
  }
  $args{quiet_option} = $args{quiet} ? "--quiet" : "";
  my $self = \%args;
  bless($self, $class);
  return $self;
}

=head2 SvnToGit#run

If converting a normal repo (either no structure or some structure),
the conversion process looks like this:

=over 4

=item *

Use git-svn to clone the SVN repo (unless C<clone> was set to false)

=item *

Go through branches in the new git repo, creating proper tags from
branches that look like tags and checking out every other branch as
a local branch

=item *

Map trunk to master

=item *

Perform optimizations on the final repo to reduce file size

=back

If converting a repo with an inconsistent structure, the process is a
bit more complicated:

=over 4

=item *

Use git-svn to clone the two parts of the SVN repo separately such
there are two repos.

=item *

Use C<git fetch> to copy commits (including branches and tags) from
the second repo to the first repo

=item *

Re-check out remote branches as local branches in the first repo

=item *

Graft the second repo onto the end of the first repo

=item *

Fix master so it points to the end of the second repo instead of the
first

=item *

Perform optimizations on the final repo to reduce file size

=back

=cut

sub run {
  my $self = shift;
  
  $self->ensure_git_present();

  if ($self->{clone}) {
    $self->clone($self->{svn_repo}, $self->{git_repo});
  } else {
    print "Since you requested not to clone, I'm assuming that you're already in the git repo.\n";
  }
  
  $self->cache_branches();
  $self->fix_tags();
  $self->fix_branches();
  $self->fix_trunk();
  $self->optimize_repo();
  chdir ".." if $self->{clone};
  
  #print "\n----------\n";
  #print "Conversion done!";
  #print " Check out $self->{git_repo}." if $self->{clone};
  #print "\n";
}

sub clone {
  my $self = shift;
  
  $self->ensure_git_svn_present();
  
  if ($self->{force}) {
    $self->run_command(qw(rm -rf), $self->{git_repo});
  }
  if (-e $self->{git_repo}) {
    die "Can't clone to '$self->{git_repo}', that directory is already present!\n";
  }
  mkdir $self->{git_repo};
  chdir $self->{git_repo};

  print "Cloning SVN repo at $self->{svn_repo} into $self->{git_repo}...\n";

  my @clone_opts;
  if ($self->{root_is_trunk}) {
    push @clone_opts, "--trunk=".$self->{svn_repo};
  } else {
    for my $opt (qw(trunk branches tags)) {
      push @clone_opts, "--$opt=$self->{$opt}" if $self->{$opt};
    }
    push @clone_opts, "-s" unless @clone_opts;
  }
  $self->run_command(qw(git svn init $self->{quiet_option} --no-metadata), @clone_opts, $self->{svn_repo});
  
  $self->run_command(qw(git config svn.authorsfile), $self->{authors}) if $self->{authors};
  
  my @fetch_opts;
  push @fetch_opts, "-r", $self->{revision} if $self->{revision};
  $self->run_command(qw(git svn fetch $self->{quiet_option}), @fetch_opts);
}

sub cache_branches {
  my $self = shift;
  $self->{remote_branches} = [map { strip($_) } `git branch -r`];
}

sub fix_tags {
  my $self = shift;
  
  print "Turning svn tags cloned as branches into real git tags...\n";
  
  my $tags_path = $self->{tags} || 'tags/';
  $tags_path .= '/' unless $tags_path =~ m{/$};
  my @tag_branches = grep m{^\Q$tags_path\E}, @{$self->{remote_branches}};

  for my $tag_branch (@tag_branches) {
    qx/git show-ref $tag_branch/;
    if ($?) {
      warn "'$tag_branch' is not a valid branch reference, so skipping..";
      next;
    }

    my($tag) = $tag_branch =~ m{^\Q$tags_path\E(.*)};
    warn "Couldn't find tag name from $tag_branch" unless length $tag;

    if (my $strip = $self->{strip_tag_prefix}) {
      $tag =~ s{^$strip}{};
    }
    
    my $subject = strip(`git log -l --pretty=format:'\%s' "$tag_branch"`);
    my $date = strip(`git log -l --pretty=format:'\%ci' "$tag_branch"`);
    $self->run_command(qw(git checkout $self->{quiet_option}), $tag_branch);
    $self->run_command("GIT_COMMITTER_DATE='$date'", qw(git tag $self->{quiet_option} -a -m), $subject, $tag, $tag_branch);
    $self->run_command(qw(git branch $self->{quiet_option} -d -r), $tag_branch);
  }
}

sub fix_branches {
  my $self = shift;
  
  print "Checking out remote branches as local branches...\n";
  
  my $tags_path = $self->{tags} || 'tags/';
  $tags_path .= '/' unless $tags_path =~ m{/$};
  my @remote_branches = grep !m{^\Q$tags_path}, @{$self->{remote_branches}};

  my $trunk = $self->{trunk} || "trunk";
  for my $branch (@remote_branches) {
    next if $branch eq $trunk;
    
    $self->run_command(qw(git checkout $self->{quiet_option}), $branch);
    $self->run_command(qw(git checkout $self->{quiet_option} -b), $branch);
  }
}

sub fix_trunk {
  my $self = shift;
  
  my $trunk = $self->{trunk} || "trunk";

  return unless grep /^\s*\Q$trunk\E\s*/, @{$self->{remote_branches}};

  print "Making sure master is trunk...\n";

  $self->run_command(qw(git checkout $self->{quiet_option}), $trunk);
  $self->run_command(qw(git branch $self->{quiet_option} -D master));
  $self->run_command(qw(git checkout $self->{quiet_option} -f -b master));
  $self->run_command(qw(git branch $self->{quiet_option} -d -r), $trunk);
}

sub optimize_repo {
  my $self = shift;
  $self->run_command(qw(git gc $self->{quiet_option}));
}

#---

sub ensure_git_present {
  my $self = shift;
  `git --version`;
  die "git --version didn't work.  Is git installed?\n" if $?;
}

sub ensure_git_svn_present {
  my $self = shift;
  `git help svn`;
  die "git help svn didn't work.  Is git-svn installed?\n" if $?;
}

sub run_command {
  my $self = shift;
  
  print "COMMAND: @_\n" if $self->{verbose};
  system @_;

  my $exit = $? >> 8;
  die "@_ exited with $exit" if $exit;

  return 1;
}

# don't need to get self here, since this is kind of a private method
sub strip {
  local $_ = shift;
  s/^\s+//; s/\s+$//;
  return $_;
}

1;

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

=cut