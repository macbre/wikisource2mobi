wikisource2mobi
===============

Converts books from WikiSource to mobi.

### Tools
* [mobiperl](https://dev.mobileread.com/trac/mobiperl)

### MobiPerl instalation

```
svn co https://dev.mobileread.com/svn/mobiperl/trunk/ mobiperl
perl -MCPAN -e shell
install Palm::PDB
install XML::Parser::Lite::Tree
install GD
install Image::BMP
install Image::Size
install HTML::TreeBuilder
install Getopt::Mixed
install Date::Parse
install Date::Format
```