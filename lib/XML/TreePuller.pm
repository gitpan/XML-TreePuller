package XML::TreePuller;

our $VERSION = '0.0.1';

use strict;
use warnings;
use Data::Dumper;

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
	
	$reader = $self->{reader} = XML::LibXML::Reader->new(@args);
	$self->{elements} = [];
	$self->{config} = {};
	$self->{finished} = 0;
	
	die "could not construct libxml reader" unless defined $reader;
		
	return $self;
	
}

sub config {
	my ($self, $path, $todo) = @_;
	
	$self->{config}->{$path} = $todo;
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
			return ();
		}
	}

	do {
		my $path;
		my $todo;
		my $ret;
		
		if(! $self->_sync) {
			return ();	
		}
		
		push(@$elements, $reader->name);
		
		$path = '/' . join('/', @$elements);	
		
		#print $path, "\n";
		
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

sub _sync {
	my ($self) = @_;
	my $reader = $self->{reader};
	my $depth = $self->{reader}->depth;
	my $elements = $self->{elements}; 

	#if we wind up at a lower level than we have
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

sub new {
	my ($class, $tree) = @_;
	
	if ($tree->[0] != XML_READER_TYPE_ELEMENT) {
		croak("must specify an element node");
	}
	
	bless($tree, $class);
	
	return $tree;
}

sub get_elements {
	my ($self, $path) = @_;
	my @results;

	$path = '' unless defined $path;

	@results = $self->_recursive_get_child_elements(split('/', $path));
	
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
	my ($tree) = @_;
	my $p = $tree->[4]; 
	my @text;
		
	return '' unless defined $p;

	for(my $i = 0; $i < scalar(@$p); $i++) {
		if ($p->[$i]->[0] == XML_READER_TYPE_TEXT || $p->[$i]->[0] == XML_READER_TYPE_CDATA) {
			push(@text, $p->[$i]->[1]);
		}
	}	
	
	return join('', @text);
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

sub _recursive_get_child_elements {
	my ($tree, @path) = @_;
	my $child_nodes = $tree->[4];
	my @results;
	my $target;
	
	if (! scalar(@path)) {
		return XML::TreePuller::Element->new($tree);
	}
	
	$target = shift(@path);
	
	return () unless defined $child_nodes;
	
	foreach (_extract_elements(@$child_nodes)) {
		next unless $_->[1] eq $target;
		
		push(@results, _recursive_get_child_elements($_, @path));
	}
	
	return @results;
}


1;

__END__

=head1 NAME

XML::TreePuller - pull interface to a tree based XML processing system

=head1 SYNOPSIS

  use XML::TreePuller;
  
  $pull = XML::TreePuller->new(location => '/what/ever/filename.xml');
  $pull = XML::TreePuller->new(location => 'http://urls.work.too/data.xml');
  $pull = XML::TreePuller->new(IO => \*FH);
  $pull = XML::TreePuller->new(string => '<xml/>');

  $pull->reader;

  $pull->config('/xml', 'short');
  $pull->config('/xml', 'subtree');
  
  while(defined($element = $pull->next)) { }
  
  $element->name;
  $element->text;
  $element->attribute('attribute_name');
  $element->get_elements('element/path');
  
    

=head1 ABOUT

This module implements a tree oriented XML pull processor using a combination of
XML::LibXML::Reader and an object-oriented interface around the output of XML::CompactTree. 
It provides a fast and convenient way to access the content of extremely large XML documents
serially. 

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

=item config

This method allows you to control the configuration of the processing engine. You specify
a path to an XML element and an instruction: short or subtree. The combination of the 
current path of the XML document in the reader and the instruction to use will generate
instances of XML::TreePuller::Element available from the "next" method.

=over 4

=item config('/path/to/element' => 'short');

When the path of the current XML element matches the path specified the 
"next" method will return an instance of XML::TreePuller::Element that
holds any attributes and will contain textual data up to the start
of another element; there will be no child elements in this element. 

=item config('/ditto' => 'subtree');

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
XML document. You can move the cursor of the reader if you want.

=back

=head1 XML::TreePuller::Element

This class is how you access the data from XML::TreePuller. 

=head2 METHODS

=over 4

=item name

Returns the name of the element as a string

=item text

Returns the text stored in the element as a string; returns an empty string if 
there is no text

=item attribute

If called with out any arguments returns a hash reference containing the
attribute names as keys and the attribute values as the data. If called with
an argument returns the value for the attribute by that name or undef
if there is no attribute by that name.

=item get_elements

Searches this element for any child elements as matched by the path supplied as
an argument. The path is of the format 'node1/node2/node3' where each node name
is seperated by a forward slash and there is no trailing or leading forwardslashes.

If called in scalar context returns the first element that matches the path; if 
called in array context returns a list of all elements that matched.

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
  	
  	$xml->config('/wiki/siteinfo/namespaces/namespace' => 'short');
  	
  	while(defined(my $element = $xml->next)) {
  		print $element->attribute('key'), ": ", $element->text, "\n";
  	}
  	
  	print "End of namespace names\n";
  }
  
  sub subtree_example {
  	my $xml = XML::TreePuller->new(string => gen_xml());
  	
  	print "Printing titles using a subtree:\n";
  	
  	$xml->config('/wiki/page' => 'subtree');
  
  	while(defined(my $element = $xml->next)) {
  		print "Title: ", $element->get_elements('title')->text, "\n";
  	}	
  	
  	print "End of titles\n";
  }
  
  sub path_example {
  	my $xml = XML::TreePuller->new(string => gen_xml());
  	
  	print "Printing path example:\n";
  	
  	$xml->config('/wiki/siteinfo', 'subtree');
  	$xml->config('/wiki/page/title', 'short');
  	
  	while(my ($matched_path, $element) = $xml->next) {
  		print "Path: $matched_path\n";
  	}
  	
  	print "End path example\n";
  }
  
  element_example(); print "\n";
  subtree_example(); print "\n";
  path_example(); print "\n";
    
