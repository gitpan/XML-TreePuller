#!/usr/bin/env perl

#things got ugly in here when XPath
#support was hammered in - should be cleaned up

package XML::TreePuller::Element;

our $VERSION = '0.1.0';

use strict;
use warnings;
use Carp qw(croak);

use XML::LibXML::Reader;
use Tree::XPathEngine::Number;
use Data::Dumper;
use Scalar::Util qw(weaken);
use Tree::XPathEngine;

sub new {
	my ($class, $tree) = @_;
	
	if ($tree->[0] != XML_READER_TYPE_ELEMENT) {
		croak("must specify an element node");
	}
	
	bless($tree, $class);

	$tree->[10] = Tree::XPathEngine->new;
	$tree->_init($tree, 0);
	
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

sub xpath {
	my @return = $_[0]->[10]->findnodes($_[1], XML::TreePuller::Element::Document->new($_[0]));
	
	if (wantarray()) {
		return @return;
	}
	
	return shift(@return);
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
	my ($self, $root, $depth) = @_;
	my @elements = $self->get_elements;
	
	$self->[10] = $root->[10];
	
	$self->[5] = undef;
	$self->[6] = $root;
	$self->[7] = $depth;
	
	weaken($self->[6]);
	
	$depth++;

	for(my $i = 0; $i < @elements; $i++) {
		my $before = $elements[$i - 1];
		my $after = $elements[$i + 1];
		
		if ($i - 1 < 0) {
			$before = undef;
		}
		
		$elements[$i]->[8] = $before;
		$elements[$i]->[9] = $after;
		
		weaken($elements[$i]->[8]);
		weaken($elements[$i]->[9]);
	}	
	
	foreach (@elements) {
		#set the parent and root of each element
		$_->[5] = $self;
		$_->[6] = $root;
		
		$_[7] = $depth;
		
		weaken($_->[5]);
		weaken($_->[6]);
		
		bless($_, 'XML::TreePuller::Element');
		
		$_->_init($root, $depth);
	}
}

#methods for Tree::XPathEngine
sub xpath_get_name {
	return name(@_);
}

sub xpath_string_value {
	return (text(@_));
}

sub xpath_get_parent_node {
	return $_[0]->[6] || XML::TreePuller::Element::Document->new($_[0]);
}

sub xpath_get_child_nodes {
	return $_[0]->get_elements;
}	

sub xpath_is_element_node {
	return 1;
}

sub xpath_is_document_node {
	return 0;
}

sub xpath_is_attribute_node {
	return 0;
}

sub xpath_to_string {
	return $_[0];
}

sub xpath_to_number {
	return Tree::XPathEngine::Number->new($_[0]->xpath_to_string);
}

sub xpath_cmp {
	return $_[0]->[7] cmp $_[1]->[7];
}

sub xpath_get_attributes {
	
	my $elt= shift;
    my $atts= $elt->attribute;
    my $rank=-1;
    my @atts= map { bless( { name => $_, value => $atts->{$_}, elt => $elt, rank => $rank -- }, 
                           'XML::TreePuller::Element::Attribute') 
                  }
                   sort keys %$atts; 
    return @atts;
}

sub xpath_get_next_sibling  {
	return $_[0]->[8];	
}

sub xpath_get_prev_sibling {
	return $_[0]->[9];
}

sub xpath_get_root_node
  { my $node= shift;
    # The parent of root is a Tree::DAG_Node::XPath::Root
    # that helps getting the tree to mimic a DOM tree
    return $node->[6]->xpath_get_parent_node; # I like this one!
  }


package XML::TreePuller::Element::Document;

use strict;
use warnings;

sub new {
	my ($class, $root) = @_;
	my $self = [ $root ];
	
	$self->[7] = -1;
	
	return bless($self, $class);
}

sub xpath_get_child_nodes   { return( $_[0]->[0] ); } 
sub xpath_get_attributes    { return (); }
sub xpath_is_document_node  { return 1   }
sub xpath_is_element_node   { return 0   }
sub xpath_is_attribute_node { return 0   }
sub xpath_get_parent_node   { return; }
sub xpath_get_root_node     { return $_[0] }
sub xpath_get_name          { return; }
sub xpath_get_next_sibling  { return; }
sub xpath_get_previous_sibling { return; }

package XML::TreePuller::Element::Attribute;

use strict;
use warnings;

sub xpath_get_value         { return $_[0]->{value}; }
sub xpath_get_name          { return $_[0]->{name} ; }
sub xpath_string_value      { return $_[0]->{value}; }
sub xpath_to_number         { return Tree::XPathEngine::Number->new( $_[0]->{value}); }
sub xpath_is_document_node  { 0 }
sub xpath_is_element_node   { 0 }
sub xpath_is_attribute_node { 1 }
sub to_string         { return qq{$_[0]->{name}="$_[0]->{value}"}; }

1;