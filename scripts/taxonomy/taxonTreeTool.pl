#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Getopt::Long;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Compara::Utils::SpeciesTree;

$| = 1;

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'scale'} = 10;

my ($help, $url, $url_core);

GetOptions('help'           => \$help,
           'url=s'          => \$url,
           'taxon_id=i'     => \$self->{'taxon_id'},
           'taxa_list=s'    => \$self->{'taxa_list'},
           'taxa_compara'   => \$self->{'taxa_compara'},
           'name=s'         => \$self->{'scientific_name'},
           'scale=f'        => \$self->{'scale'},
           'index'          => \$self->{'build_leftright_index'},
           'genetree_dist'  => \$self->{'genetree_dist'},
           'url_core=s'     => \$url_core,
          );

if($self->{'taxa_list'}) { 
  $self->{'taxa_list'} = [ split(",",$self->{'taxa_list'}) ];
}

if ($self->{'taxon_id'} && $self->{'scientific_name'}) {
  print "You can't use -taxon_id and -name together. Use one or the other.\n\n";
  exit 3;
}

if ($help) { usage(); }

$self->{'comparaDBA'}  = Bio::EnsEMBL::Hive::URLFactory->fetch($url . ';type=compara') if($url);
unless(defined($self->{'comparaDBA'})) {
  print("no url\n\n");
  usage();
}

Bio::EnsEMBL::Registry->no_version_check(1);

if ($self->{'taxon_id'}) {
    fetch_by_ncbi_taxon_id($self);
} elsif ($self->{'scientific_name'}) {
    fetch_by_scientific_name($self);
} elsif ($self->{'taxa_list'}) {
    fetch_by_ncbi_taxa_list($self);
} elsif ($self->{'build_leftright_index'}) {
    update_leftright_index($self);
} elsif ($self->{'taxa_compara'}) {
    fetch_compara_ncbi_taxa($self);
} elsif ($url_core and ($self->{'taxon_id'} or $self->{'scientific_name'})) {
    load_taxonomy_in_core($self);
} else {
    usage();
}

#cleanup memory
if($self->{'root'}) {
#  print("ABOUT TO MANUALLY release tree\n");
  $self->{'root'}->release_tree;
  $self->{'root'} = undef;
#  print("DONE\n");
}

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "testTaxonTree.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -url <string>          : connect to compara at url e.g. mysql://ensro\@ecs2:3365/ncbi_taxonomy\n";
  print "  -taxon_id <int>        : print tree by taxon_id\n";
  print "  -taxa_list <string>    : print tree by taxa list e.g. \"9606,10090\"\n";
  print "  -taxa_compara          : print tree of the taxa in compara\n";
  print "  -name <string>         : print tree by scientific name e.g. \"Homo sapiens\"\n";
  print "  -scale <int>           : scale factor for printing tree (def: 10)\n";
  print "  -mini                  : minimize tree\n";
  print "  -url_core              : core database url used to load the taxonomy info in the meta table\n";
  print "                           to be used with -taxon_id or -name\n";
  print "                           mysql://login:password\@ecs2:3364/a_core_db\n";
  print " -index                  : build left and right node index to speed up subtree queries.\n";
  print "                           to be used only by the person who sets up a taxonomy database.\n";
  print "taxonTreeTool.pl v1.1\n";

  exit(1);
}

sub fetch_by_ncbi_taxon_id {
  my $self = shift;
  my $taxonDBA = $self->{'comparaDBA'}->get_NCBITaxonAdaptor;
  my $node = $taxonDBA->fetch_node_by_taxon_id($self->{'taxon_id'});
  $node->no_autoload_children;
  my $root = $node->root;
  
  $root->print_tree($self->{'scale'});
  print "classification: ",$node->classification,"\n";
  if ($node->rank eq 'species') {
    print "scientific name: ",$node->binomial,"\n";
    if (defined $node->common_name) {
      print "common name: ",$node->common_name,"\n";
    } else {
      print "no common name\n";
    }
  }
  $self->{'root'} = $root;
}

sub fetch_by_scientific_name {
  my $self = shift;
  my $taxonDBA = $self->{'comparaDBA'}->get_NCBITaxonAdaptor;
  my $node = $taxonDBA->fetch_node_by_name($self->{'scientific_name'});
  $node->no_autoload_children;
  my $root = $node->root;

  $root->print_tree($self->{'scale'});
  print "classification: ",$node->classification,"\n";
  if ($node->rank eq 'species') {
    print "scientific name: ",$node->binomial,"\n";
    if (defined $node->common_name) {
      print "common name: ",$node->common_name,"\n";
    } else {
      print "no common name\n";
    }
  }
  $self->{'root'} = $root;
}

sub fetch_by_ncbi_taxa_list {
  my $self = shift;
  
  my $root = Bio::EnsEMBL::Compara::Utils::SpeciesTree->create_species_tree(
    -COMPARA_DBA    => $self->{'comparaDBA'},
    -SPECIES_SET    => undef,
    -NO_PREVIOUS    => 1,
    -RETURN_NCBI_TREE       => 1,
    -EXTRATAXON_SEQUENCED   => $self->{'taxa_list'},
  );

  $root->print_tree($self->{'scale'});
  $root->flatten_tree->print_tree($self->{'scale'});
  $self->{'root'} = $root;
}


sub get_distances_from_genetrees {
    my $self = shift;
    my $node = shift;
    foreach my $child (@{$node->children}) {
        my $sth = $self->{$child->get_child_count ? 'sth_dist_1' : 'sth_dist_2'};
        $sth->execute($node->taxon_id, $child->taxon_id);
        my @allval = sort {$a <=> $b} map {$_->[0]} @{$sth->fetchall_arrayref};
        $sth->finish;
        my $n = scalar(@allval);
        if ($n) {
            my $i = int($n/2);
            my $val = $allval[$i];
            print $node->taxon_id, "/", $node->name, " ", $child->taxon_id, "/", $child->name, " $val ($n/$i)\n";
            $child->distance_to_parent($val);
        }
        $self->get_distances_from_genetrees($child);
    }
}

sub fetch_compara_ncbi_taxa {
  my $self = shift;
  
  printf("fetch_compara_ncbi_taxa\n");
  
  my $root = Bio::EnsEMBL::Compara::Utils::SpeciesTree->create_species_tree(
    -COMPARA_DBA    => $self->{'comparaDBA'},
    -RETURN_NCBI_TREE       => 1,
  );

  if ($self->{'genetree_dist'}) {
    # Used to get the average branch lengths from the trees
    my $sql_dist_1 = 'SELECT distance_to_parent FROM gene_tree_root JOIN gene_tree_node gtn USING (root_id) JOIN gene_tree_node_attr gtna USING (node_id) JOIN gene_tree_node_attr gtnap ON gtnap.node_id = parent_id WHERE clusterset_id = "default" AND gtna.node_type = "speciation" AND gtnap.node_type = "speciation" AND gtnap.taxon_id = ? AND gtna.taxon_id = ?';
    my $sql_dist_2 = 'SELECT distance_to_parent FROM gene_tree_root JOIN gene_tree_node gtn USING (root_id) JOIN seq_member USING (seq_member_id) JOIN gene_tree_node_attr gtnap ON gtnap.node_id = parent_id WHERE clusterset_id = "default" AND gtnap.node_type = "speciation" AND gtnap.taxon_id = ? AND seq_member.taxon_id = ?';
    $self->{'sth_dist_1'} = $self->{'comparaDBA'}->dbc->prepare($sql_dist_1);
    $self->{'sth_dist_2'} = $self->{'comparaDBA'}->dbc->prepare($sql_dist_2);
    $self->get_distances_from_genetrees($root);
  }
  $root->print_tree($self->{'scale'});
  
  my $newick = $root->newick_format;
  print("$newick\n");

  print $root->newick_format('ncbi_taxon'), "\n";

  $self->{'root'} = $root;
}

sub update_leftright_index {
  my $self = shift;

  my $taxonDBA = $self->{'comparaDBA'}->get_NCBITaxonAdaptor;
  my $root = $taxonDBA->fetch_node_by_name('root');
  $root = $root->root;
  print STDERR "Starting indexing...\n";
  build_store_leftright_indexing($self, $root);
  $self->{'root'} = $root;
}

sub build_store_leftright_indexing {
  my $self = shift;
  my $node = shift;
  my $counter =shift;

  my $taxonDBA = $self->{'comparaDBA'}->get_NCBITaxonAdaptor;

  $counter = 1 unless ($counter);
  
  $node->left_index($counter++);
  foreach my $child_node (@{$node->sorted_children}) {
    $counter = build_store_leftright_indexing($self, $child_node, $counter);
  }
  $node->right_index($counter++);
  $taxonDBA->update($node);
  $node->release_children;
  print STDERR "node_id = ", $node->node_id, " indexed and stored, li = ",$node->left_index," ri = ",$node->right_index,"\n";
  return $counter;
}

sub load_taxonomy_in_core {
  my $self = shift;
  $self->{'coreDBA'}  = Bio::EnsEMBL::Hive::URLFactory->fetch($url_core . ';type=core') if($url_core);
  unless(defined($self->{'coreDBA'})) {
    print("no core url\n\n");
    usage();
  }
  my $taxonDBA = $self->{'comparaDBA'}->get_NCBITaxonAdaptor;
  my $node;
  if (defined $self->{'taxon_id'}) {
    $node = $taxonDBA->fetch_node_by_taxon_id($self->{'taxon_id'});
  } else {
    $node = $taxonDBA->fetch_node_by_name($self->{'scientific_name'});
  }
  unless ($node->rank eq 'species') {
    print "ERROR: taxon_id=",$self->{'taxon_id'},", '",$node->name,"' is rank '",$node->rank,"'.\n";
    print "It is not a rank 'species'. So it can't be loaded.\n\n";
    exit 2;
  }
  $node->no_autoload_children;
  my $root = $node->root;

  my $mc = $self->{'coreDBA'}->get_MetaContainer;
  $mc->delete_key('species.classification');
  $mc->delete_key('species.common_name');
  $mc->delete_key('species.taxonomy_id');
  print "Loading species.taxonomy_id = ",$node->node_id,"\n";
  $mc->store_key_value('species.taxonomy_id',$node->node_id);
  if (defined $node->common_name) {
    $mc->store_key_value('species.common_name',$node->common_name);
    print "Loading species.common_name = ",$node->common_name,"\n";
  }
  my @classification = split(",",$node->classification(","));
  foreach my $level (@classification) {
    print "Loading species.classification = ",$level,"\n";
    $mc->store_key_value('species.classification',$level);
  }
  $self->{'root'} = $root;
}

