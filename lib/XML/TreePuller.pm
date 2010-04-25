package XML::TreePuller;

our $VERSION = '0.1.1';

use strict;
use warnings;
use Data::Dumper;
use Carp qw(croak carp);

use XML::LibXML::Reader;

use XML::TreePuller::Element;

our $NO_XS;

BEGIN {
	if (! defined(eval { require XML::CompactTree::XS; })) {
		$NO_XS = 1;
		require XML::CompactTree;
	}

}

sub new {
	my ($class, @args) = @_;
	my $self = {};
	my $reader;
	
	bless($self, $class);
	
	$self->{elements} = [];
	$self->{config} = {};
	$self->{finished} = 0;

	$Carp::CarpLevel++;
	$reader = $self->{reader} = XML::LibXML::Reader->new(@args);
	$Carp::CarpLevel--;
	
	#arg how do you get error messages out of libxml reader?	
	croak("could not construct libxml reader") unless defined $reader;
		
	return $self;
}

sub parse {
	my ($class, @args) = @_;
	
	return $class->new(@args)->next;
}

sub iterate_at {
	my ($self, $path, $todo) = @_;
	
	croak("must specify match and instruction") unless defined $path && defined $todo;
	
	$self->{config}->{$path} = $todo;
	
	return undef;
}

sub config {
	#turn this warning on later
	#carp "config() is depreciated, use iterate_at() instead";
	
	return iterate_at(@_);
}

sub next {
	my ($self) = @_;
	my $reader = $self->{reader};
	my $elements = $self->{elements};
	my $config = $self->{config};
	my $ret;
	
	return () if $self->{finished};

	if ($reader->nodeType != XML_READER_TYPE_ELEMENT) {
		if (! $self->_find_next_element) {
			#no more elements available in the document
			return ();
		}
	}
	
	#the reader came in already sitting on an element so we have to 
	#iterate at the end of the loop
	do {
		my $path;
		my $todo;
		my $ret;
		
		if(! $self->_sync) {
			#ran out of data in the document
			return ();	
		}
		
		push(@$elements, $reader->name);
		
		$path = '/' . join('/', @$elements);	
		
		#handle the default case where no config is specified
		if (scalar(keys(%$config)) == 0) {
			$self->{finished} = 1;	
			
			if (wantarray()) {
				return($path, $self->_read_subtree);
			}
			
			return $self->_read_subtree;
		}
				
		if (defined($todo = $config->{$path})) {
			if ($todo eq 'short') {
				$ret = $self->_read_element;
			} elsif ($todo eq 'subtree') {
				$ret = $self->_read_subtree;
			} else {
				die "invalid todo specified: $todo";
			}
			
			if (wantarray()) {
				return($path, $ret);
			} 
			
			return $ret;
		}
		
	} while ($self->_find_next_element);
	
	return ();
}

sub reader {
	return $_[0]->{reader};
}

#private methods

#get the reader to a point where it is in sync with
#our internal element list
sub _sync {
	my ($self) = @_;
	my $reader = $self->{reader};
	my $depth = $self->{reader}->depth;
	my $elements = $self->{elements}; 

	#if we are at a higher level than we have
	#tracked to we need to get back to the same
	#depth as our element list to properly process
	#data again
	while(scalar(@$elements) < $reader->depth) {
		my $ret = $reader->nextElement;
		
		if ($ret == -1) {
			die "libxml read error";
		} elsif ($ret == 0) {
			$self->{finished} = 1;
			return 0;
		}
	}

	#handle the case where the reader is at a lower
	#depth than we have tracked to
	splice(@$elements, $reader->depth);
	
	return 1;
}


sub _find_next_element {
	my ($self) = @_;
	my $reader = $self->{reader};
	my $ret;
	
	if (! ($ret = $reader->nextElement)) {
		$self->{finished} = 1;
		
		return 0;
	} elsif ($ret == -1) {
		die "libxml read error";
	}
	
	return 1;
}

sub _read_subtree {
	my ($self) = @_;
	my $reader = $self->{reader};
	my $elements = $self->{elements};
	
	my $tree = XML::TreePuller::Element->new(_read_tree($reader));
	
	if (! defined($tree)) {
		$self->{finished} = 1;
		return undef;
	}
	
	return $tree;
}

sub _read_element {
	my ($self) = @_;
	my $reader = $self->{reader};
	my $is_empty = $reader->isEmptyElement;
	my $new;
	my %attr;
	my $node_type;
	my $ret;
	
	$new->[0] = 1;
	$new->[1] = $reader->name;
	$new->[2] = 0;
	$new->[3] = \%attr;
	$new->[4] = [];
	
	
	if ($reader->hasAttributes && $reader->moveToFirstAttribute == 1) {
		do {
			my $name = $reader->name;
			my $val = $reader->value;
			
			$attr{$name} = $val;
		} while($reader->moveToNextAttribute == 1);
	}


	$ret = $reader->read;
	
	if ($ret == -1) {
		die "libxml read error";
	} elsif ($ret == 0) {
		return undef;
	}

	if ($is_empty) {
		return XML::TreePuller::Element->new($new);
	}

	$node_type = $reader->nodeType;
	
	while($node_type != XML_READER_TYPE_ELEMENT && $node_type != XML_READER_TYPE_END_ELEMENT) {
		$node_type = $reader->nodeType;
		
		if ($node_type == XML_READER_TYPE_TEXT || $node_type == XML_READER_TYPE_CDATA) {
			push(@{$new->[4]}, [ $node_type, $reader->value ]);
		}

		$ret = $reader->read;
		
		if ($ret == -1) {
			die "libxml read error";
		} elsif ($ret == 0) {
			return undef;
		}
		
		$node_type = $reader->nodeType;

	}
	
	return XML::TreePuller::Element->new($new);
}

sub _read_tree {
	my ($r) = @_;
	
	if ($NO_XS) {
		return XML::CompactTree::readSubtreeToPerl($r, 0);
	}
	
	return XML::CompactTree::XS::readSubtreeToPerl($r, 0);
}

1;

__END__

=head1 NAME

XML::TreePuller - pull interface to work with XML document fragments

=head1 SYNOPSIS

  use XML::TreePuller;
  
  $pull = XML::TreePuller->new(location => '/what/ever/filename.xml');
  $pull = XML::TreePuller->new(location => 'http://urls.too/data.xml');
  $pull = XML::TreePuller->new(IO => \*FH);
  $pull = XML::TreePuller->new(string => '<xml/>');

  #parse the document and return the root element
  #takes same arguments as new()
  $element = XML::TreePuller->parse(%ARGS); 

  $pull->reader; #return the XML::LibXML::Reader object

  $pull->iterate_at('/xml', 'short'); #read the first part of an element
  $pull->iterate_at('/xml', 'subtree'); #read the element and subtree
  
  while($element = $pull->next) { }
  
  $element->name;
  $element->text; #fetch text for the element and all children
  $element->attribute('attribute_name'); #get attribute value
  $element->attribute; #returns hashref of attributes
  $element->get_elements; #return all child elements 
  $element->get_elements('element/path'); #elements from path
  $element->xpath('/xml'); #search using a XPath
  
=head1 ABOUT

This module implements a tree oriented XML pull processor providing fast and 
convenient access to the content of extremely large XML documents serially. Tree
oriented means the data is returned from the engine as a tree of data replicating the
structure of the original XML document. Pull processor means you sequentially ask
the engine for more data (the opposite of SAX). This engine also supports breaking
the document into fragments so the trees are small enough to fit into RAM.

=head1 STATUS

This software is currently ALPHA quality - the only known use is
MediaWiki::DumpFile which is itself becoming tested in production. The
API is not stable and there may be bugs: please report success and
failure to the author below. 

=head1 XML::TreePuller

=head2 METHODS

=over 4

=item new

The constructor for this class returns an instance of itself; all arguments are passed
straight on to XML::LibXML::Reader when it is constructed. See the documentation for
a full specification of what you can use but for quick reference:

=over 4

=item new(location => '/what/ever/filename.xml');

=item new(location => 'http://urls.work.too/data.xml');

=item new(string => $xml_data);

=item new(IO => \*FH);

=back

=item parse

This method takes the same arguments as new() but parses the entire document into
an element and returns it; you can use this if you don't need to break the document
into chunks. 

=item iterate_at

This method allows you to control the configuration of the processing engine; you specify
two arguments: a path to an XML element and an instruction. The engine will move along
node by node through the document and keep track of the full path to the current element. 
The combination of the current path of the XML document in the reader and the instruction
to use will cause instances of XML::TreePuller::Element to be available from the "next" method.

If iterate_at() is never called then the entire document will be read into a single element
at the first invocation of next().

=over 4

=item iterate_at('/path/to/element' => 'short');

When the path of the current XML element matches the path specified the 
"next" method will return an instance of XML::TreePuller::Element that
holds any attributes and will contain textual data up to the start
of another element; there will be no child elements in this element. 

=item iterate_at('/ditto' => 'subtree');

When the path of the current XML element matches the path specified the
"next" method will return an instance of XML::TreePuller::Element that 
holds the attributes for the element and all of the element textual data
and child elements. 

=back

=item next

This method is the iterator for the processing system. Each time an instruction is
matched it will return an instance of XML::TreePuller::Element. When called in
scalar context returns a reference to the next available element or undef when
no more data is available. When called in list context it returns a two item
list with the first item being the path to the node that was matched and the
second item being the next available element; returns an empty list when 
there is no more data to be processed. 

The returned path will always be a full path in the document starting at the
root element and ending in the element that ultimately matched. 

=item reader

Returns the instance of XML::LibXML::Reader that we are using to parse the
XML document. You can move the cursor of the reader if you want but keep this in mind:
if you move the cursor of the reader to an element in the document that is at a higher
level than the reader was sitting at when you moved it then the reader must move the
cursor to an element that was at the same depth in the document as it was at the start;
this may cause some parts of the document to be thrown out that you are not expecting. 

=back

=head1 XML::TreePuller::Element

This class is how you access the data from XML::TreePuller. XML::TreePuller::Element is 
implemented as a set of methods that operate on arrays as returned by XML::CompactTree; 
you are free to work with XML::TreePuller::Element objects just as you would work with
data returned from XML::CompactTree::readSubtreeToPerl() and such. 

=head2 METHODS

=over 4

=item name

Returns the name of the element as a string

=item text

Returns the text stored in the element and all subelements as a string; 
returns an empty string if there is no text

=item attribute

If called with out any arguments returns a hash reference containing the
attribute names as keys and the attribute values as the data. If called with
an argument returns the value for the attribute by that name or undef
if there is no attribute by that name.

=item get_elements

Searches this element for any child elements as matched by the path supplied as
an argument. The path is of the format 'node1/node2/node3' where each node name
is seperated by a forward slash and there is no trailing or leading forwardslashes. 
If no path is specified it returns all of the child nodes.

If called in scalar context returns the first element that matches the path; if 
called in array context returns a list of all elements that matched.

=item xpath

Perform an XPath query on the element and return the results; if called in list
context you'll get all of the elements that matched. If called in scalar context
you'll get the first element that matched. XPath support is currently EXPERIMENTAL. 

=back

=head1 FURTHER READING

=over 4

=item XML::TreePuller::CookBook::Intro

Gentle introduction to parsing using Atom as an example.

=item XML::TreePuller::CookBook::Performance

High performance processing of Wikipedia dump files.

=back

=head1 LIMITATIONS

=over 4

=item

XPath support is EXPERIMENTAL (even more so than the rest of this module)

=item

There is only support for elements, text in elements, and CDATA blocks - other features
of XML are not part of the API and are not tested but may bleed through from the underlying
modules used to build this system. If you have an idea on how to add support for these
extra features the author is soliciting feedback and patches. 

=item 

Things are pretty arbitrary right now as this module started life as the heart of 
MediaWiki::DumpFile; it would be nice to bring in more formal XML processing 
concepts.

=back

=head1 ATTRIBUTION

With out the following people this module would not be possible:

=over 4

=item Andrew Rodland

My Perl mentor and friend, his influence has helped me everywhere.

=item Petr Pajas

As the maintainer of XML::LibXML and creator of XML::CompactTree this
module would not be possible with out building on his great work.

=item Michel Rodriguez

For creating Tree::XPathEngine which made adding XPath support
a one day exercise. 

=back

=head1 AUTHOR

Tyler Riddle, C<< <triddle at cpan.org> >>