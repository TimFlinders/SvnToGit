#!/bin/bash

set -e

this_script=$(readlink -f $0)
this_dir=`dirname $this_script`
fixtures_dir=$this_dir/fixtures
fixture_dir=$fixtures_dir/standard_layout
mock_remote_repo=$fixture_dir/repo
mock_local_repo=$fixture_dir/wc

rm -rf $fixture_dir
mkdir -p $fixture_dir

svnadmin create --pre-1.4-compatible $mock_remote_repo
svn co file://$mock_remote_repo $mock_local_repo
cd $mock_local_repo

svn mkdir trunk branches tags 
echo "Lorem ipsum dolor sit amet" > trunk/test.txt
svn add trunk/test.txt
svn commit -m "Initial commit" --username john
svn up

echo "Add another line from trunk, rev 2" >> trunk/test.txt
svn commit -m "Update test.txt from trunk" --username john
svn up

echo "Add another line from trunk, rev 3" >> trunk/test.txt
svn commit -m "Update test.txt from trunk, again" --username john
svn up

svn copy trunk tags/v0.1.0
svn commit -m "Make 'v0.1.0' tag" --username jane
svn up

echo "Add another line from trunk, rev 5" >> trunk/test.txt
svn add trunk/test.txt
svn commit -m "Update test.txt from trunk, yet again" --username jane
svn up

svn copy trunk branches/foo
svn commit -m "Make 'foo' branch" --username joe
svn up

echo "Add another line from foo, rev 7" >> branches/foo/test.txt
svn commit -m "Update test.txt from foo" --username joe
svn up

echo "Add another line from foo, rev 8" >> branches/foo/test.txt
svn commit -m "Update test.txt from foo, again" --username joe
svn up

svn copy trunk tags/v1.0.0
svn commit -m "Make 'v1.0.0' tag" --username jane
svn up

echo "Add another line from trunk, rev 10" >> trunk/test.txt
svn commit -m "Update test.txt from trunk for the fourth time" --username jane
svn up

echo "john = John Smith <john@smith.com>" >> $fixture_dir/authors.txt
echo "jane = Jane Doe <jane@doe.com>" >> $fixture_dir/authors.txt
echo "joe = Joe Schmoe <joe@schmoe.com>" >> $fixture_dir/authors.txt