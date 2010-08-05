#!/bin/bash

set -e

rm -rf /var/svn/svn2git-test /tmp/svn
svnadmin create /var/svn/svn2git-test
svn co file:///var/svn/svn2git-test /tmp/svn
cd /tmp/svn
echo "Lorem ipsum dolor sit amet" > test.txt
svn add test.txt
svn commit -m "Initial commit"
echo "Here's another line we added in rev 2" >> test.txt
svn commit -m "Update test.txt"
echo "And another line we added in rev 3" >> test.txt
svn commit -m "Update test.txt, again"
svn mkdir trunk branches tags
svn commit -m "Add trunk, branches, tags"
svn mv test.txt trunk
svn commit -m "Move everything to trunk"
echo "Add another line from trunk, rev 6" >> trunk/test.txt
svn commit -m "Update test.txt from trunk"
svn up
svn copy trunk branches/foo
svn commit -m "Make 'foo' branch"
echo "Add another line from foo, rev 8" >> branches/foo/test.txt
svn commit -m "Update test.txt from foo"
echo "Add another line from trunk, rev 9" >> trunk/test.txt
svn commit -m "Update test.txt finally, from trunk"
