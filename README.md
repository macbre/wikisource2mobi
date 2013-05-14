wikisource2mobi
===============

Converts HTML books from various places (including [WikiSource](http://en.wikisource.org/)) to EPUB / MOBI.

### Dependencies

The following PERL modules are required:

* EBook::EPUB
* HTML::TreeBuilder::XPath

and ``ebook-convert`` binary from Calibre (to generate MOBI from EPUB book).

### How to run it?

```
./convert.pl <book YAML definition>
```

### Readers

Generated EPUB / MOBI files can be read using your favourite reader or one of the following desktop applications:

* [fbreader](http://fbreader.org/)
* [EBook viewer from Calibre](http://calibre-ebook.com/)
* [GutenPy](http://gutenpy.sourceforge.net/)
* [Lucidor](http://lucidor.org/lucidor/)

### Books

All titles available in this repository are in [public domain](http://en.wikipedia.org/wiki/public_domain) - were first published over 70 years ago.
