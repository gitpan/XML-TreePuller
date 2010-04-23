package XML::TreePuller;

our $VERSION = '0.1.0_01';

use strict;
use warnings;
use Data::Dumper;
use Carp qw(croak carp);

use XML::LibXML::Reader;

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

sub iterate_at {
	my ($self, $path, $todo) = @_;
	
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

package XML::TreePuller::Element;

use strict;
use warnings;
use Carp qw(croak);

use XML::LibXML::Reader;

use Data::Dumper;
use Scalar::Util qw(weaken);

sub new {
	my ($class, $tree) = @_;
	
	if ($tree->[0] != XML_READER_TYPE_ELEMENT) {
		croak("must specify an element node");
	}
	
	bless($tree, $class);

	$tree->_init($tree);
	
	return $tree;
}

sub get_elements {
	my ($self, $path) = @_;
	my @results;

	if (! defined($path)) {
		@results = _extract_elements(@{$self->[4]});
	} else {
		@results = $self->_recursive_get_child_elements(split('/', $path));		
	}

	if (wantarray()) {
		return @results;
	}
	
	return shift(@results);
}

sub name {
	my ($tree) = @_;
	
	return $tree->[1];
}

sub text {
	my ($self) = @_;
	my @content;
	
	foreach (@{$self->[4]}) {
		if ($_->[0] == XML_READER_TYPE_TEXT || $_->[0] == XML_READER_TYPE_CDATA) {
			push(@content, $_->[1]);
		} elsif ($_->[0] == XML_READER_TYPE_ELEMENT) {
			push(@content, $_->text);
		}
	}
	
	return join('', @content);
}

sub attribute {
	my ($tree, $name) = @_;
	my $attr = $tree->[3];
	
	$attr = {} unless defined $attr;

	if (! defined($name)) {
		return $attr;
	}
	
	return $attr->{$name};
}

#private methods
sub _extract_elements {
	return grep { $_->[0] == XML_READER_TYPE_ELEMENT } @_;	
}

#an easier to understand algorithm would be nice
sub _recursive_get_child_elements {
	my ($tree, @path) = @_;
	my $child_nodes = $tree->[4];
	my @results;
	my $target;
	
	if (! scalar(@path)) {
		return $tree;
	}
	
	$target = shift(@path);
	
	return () unless defined $child_nodes;
	
	foreach (_extract_elements(@$child_nodes)) {
		next unless $_->[1] eq $target;
		
		push(@results, _recursive_get_child_elements($_, @path));
	}
	
	return @results;
}

sub _init {
	my ($self, $root) = @_;
	
	foreach ($self->get_elements) {
		#set the parent and root of each element
		$_->[5] = $self;
		$_->[6] = $root;
		
		weaken($_->[5]);
		weaken($_->[6]);
		
		bless($_, 'XML::TreePuller::Element');
		
		$_->_init($root);
	}	
}

sub _get_parent {
	return $_[0]->[5];
}

sub _get_root {
	return $_[0]->[6];
}

sub _get_children {
	return (@{$_[0]->[4]});
}

sub _get_attr_names {
	return(keys(%{$_[0]->[3]}));
}

1;

__END__

=head1 NAME

XML::TreePuller - pull interface to work with XML document fragments

=head1 SYNOPSIS

  use XML::TreePuller;
  
  $pull = XML::TreePuller->new(location => '/what/ever/filename.xml');
  $pull = XML::TreePuller->new(location => 'http://urls.work.too/data.xml');
  $pull = XML::TreePuller->new(IO => \*FH);
  $pull = XML::TreePuller->new(string => '<xml/>');

  $pull->reader; #return the XML::LibXML::Reader object

  $pull->iterate_at('/xml', 'short'); #read the first part of an element
  $pull->iterate_at('/xml', 'subtree'); #read the element and subtree
  
  while(defined($element = $pull->next)) { }
  
  $element->name;
  $element->text; #recursively fetch text for the element and all children
  $element->attribute('attribute_name'); #get attribute value by name
  $element->attribute; #returns hashref of attributes
  $element->get_elements('element/path'); #return child elements that match the path
  $element->get_elements; #return all child elements 
  

=head1 ABOUT

This module implements a tree oriented XML pull processor using a combination of
XML::LibXML::Reader and an object-oriented interface around the output of XML::CompactTree. 
It provides a fast and convenient way to access the content of extremely large XML documents
serially. 

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

=back

=head1 LIMITATIONS

=over 4

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

=head1 EXAMPLE

  use strict;
  use warnings;
  
  use XML::TreePuller;
  
  sub gen_xml {
    	return <<EOF
    	
  <wiki version="0.3">
  
  <!-- schema says that there is always 1 siteinfo and zero or more page 
    elements follow -->
  <siteinfo>
    <sitename>ExamplePedia</sitename>
    <url>http://example.pedia/</url>
    <namespaces>
      <namespace key="-1">Special</namespace>
      <namespace key="0" />
      <namespace key="1">Talk</namespace>
    </namespaces>
  </siteinfo>
  
  <page>
    <title>A good article</title>
    <text>Some good content</text>
  </page>    
  
  <page>
    <title>A bad article</title>
    <text>Some bad content</text>
  </page>
  
  </wiki>
    	  	
  EOF
  }
  
  sub element_example {
  	my $xml = XML::TreePuller->new(string => gen_xml());
  	
  	print "Printing namespace names using configuration style:\n";
  	
  	$xml->iterate_at('/wiki/siteinfo/namespaces/namespace' => 'short');
  	
  	while(defined(my $element = $xml->next)) {
  		print $element->attribute('key'), ": ", $element->text, 
  			"\n";
  	}
  	
  	print "End of namespace names\n";
  }
  
  sub subtree_example {
  	my $xml = XML::TreePuller->new(string => gen_xml());
  	
  	print "Printing titles using a subtree:\n";
  	
  	$xml->iterate_at('/wiki/page' => 'subtree');
  
  	while(defined(my $element = $xml->next)) {
  		print "Title: ", $element->get_elements('title')->text, 
  			"\n";
  	}	
  	
  	print "End of titles\n";
  }
  
  sub path_example {
  	my $xml = XML::TreePuller->new(string => gen_xml());
  	
  	print "Printing path example:\n";
  	
  	$xml->iterate_at('/wiki/siteinfo', 'subtree');
  	$xml->iterate_at('/wiki/page/title', 'short');
  	
  	while(my ($matched_path, $element) = $xml->next) {
  		print "Path: $matched_path\n";
  	}
  	
  	print "End path example\n";
  }
  
  element_example(); print "\n";
  subtree_example(); print "\n";
  path_example(); print "\n";
    
  __END__
  
  Output:
  
  Printing namespace names using configuration style:
  -1: Special
  0: 
  1: Talk
  End of namespace names

  Printing titles using a subtree:
  Title: A good article
  Title: A bad article
  End of titles

  Printing path example:
  Path: /wiki/siteinfo
  Path: /wiki/page/title
  Path: /wiki/page/title
  End path example
  
=head1 AUTHOR

Tyler Riddle, C<< <triddle at gmail.com> >>