#!/bin/bash

set -e

fixtures_dir=$PWD/test/fixtures
mock_remote_repo=fixtures_dir/stitch-test.svn
mock_local_repo=fixtures_dir/stitch-test

rm -rf $fixtures_dir

svnadmin create $mock_remote_repo
svn co $mock_remote_repo $mock_local_repo
cd $mock_local_repo
echo "Lorem ipsum dolor sit amet" > test.txt
svn add test.txt
echo "Lorem ipsum dolor sit amet" > test2.txt
svn add test2.txt
svn commit -m "Initial commit"
echo "Here's another line we added in rev 2" >> test.txt
svn commit -m "Update test.txt"
echo "And another line we added in rev 3" >> test.txt
svn commit -m "Update test.txt, again"
svn mkdir trunk branches tags
svn commit -m "Add trunk, branches, tags"
svn mv test.txt trunk
svn commit -m "Move everything to trunk"
svn mv test2.txt trunk
svn commit -m "Oops, forgot to include test2.txt"
echo "Add another line from trunk, rev 6" >> trunk/test.txt
svn commit -m "Update test.txt from trunk"
svn up
svn copy trunk branches/foo
svn commit -m "Make 'foo' branch"
echo "Add another line from foo, rev 8" >> branches/foo/test.txt
svn commit -m "Update test.txt from foo"
echo "Add another line from trunk, rev 9" >> trunk/test.txt
svn commit -m "Update test.txt finally, from trunk"