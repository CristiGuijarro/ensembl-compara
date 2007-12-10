#!/usr/local/ensembl/bin/perl -w

use strict;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;

my $dba = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor
  (-host => 'compara1',
   -port => 3306,
   -user => 'ensro',
   -dbname => 'avilella_ensembl_compara_48');

my $doit = 1;

$|=1;

my ($sql, $sth);

if ($doit) {

# Check data consistency between pt* tables on node_id
######################################################

  $sql = "select count(*) from protein_tree_member ptm left join protein_tree_node ptn on ptm.node_id=ptn.node_id where ptn.node_id is NULL";
  
  $sth = $dba->dbc->prepare($sql);
  $sth->execute;
  
  while (my $aref = $sth->fetchrow_arrayref) {
    #should 0, if not delete culprit node_id in protein_tree_member
    my ($count) = @$aref;
    if ($count == 0) {
      print "PASSED: protein_tree_member versus protein_tree_node is consistent\n";
    } else {
      print STDERR "ERROR: protein_tree_member versus protein_tree_node is NOT consistent\n";
      print STDERR "ERROR: USED SQL : $sql\n";
    }
  }
  
  $sth->finish;
  
  $sql = "select count(*) from protein_tree_tag ptt left join protein_tree_node ptn on ptt.node_id=ptn.node_id where ptn.node_id is NULL";
  
  $sth = $dba->dbc->prepare($sql);
  $sth->execute;
  
  while (my $aref = $sth->fetchrow_arrayref) {
    #should be 0, if not delete culprit node_id in protein_tree_tag
    my ($count) = @$aref;
    if ($count == 0) {
      print "PASSED: protein_tree_tag versus protein_tree_node is consistent\n";
    } else {
      print STDERR "ERROR: protein_tree_tag versus protein_tree_node is NOT consistent\n";
      print STDERR "ERROR: USED SQL : $sql\n";
    }
  }
  
  $sth->finish;


# check for unique member presence in ptm
#########################################

  $sql = "select member_id from protein_tree_member group by member_id having count(*)>1";
  
  #This should return 0 rows. 
  
  $sth = $dba->dbc->prepare($sql);
  
  # If no duplicate, each select should return an empty row;
  $sth->execute;
  
  my $ok = 1;
  while (my $aref = $sth->fetchrow_arrayref) {
    my ($member_id) = @$aref;
    print STDERR "ERROR: some member duplicates in protein_tree_member! This can happen if there are remains of broken clusters in the db that you haven't deleted yet. Usually before merging to the compara production db\n";
    print STDERR "ERROR: USED SQL : $sql\n";
    $ok = 0;
    last;
  }
  print "PASSED: no member duplicates in protein_tree_member\n" if ($ok);
  

## # check for unique member presence in ptm but without considering singletons
## ############################################################################
## 
##   $sql = 'select * from protein_tree_member ptm, protein_tree_node ptn where 0<abs(ptn.left_index-ptn.right_index) and ptn.node_id=ptm.node_id group by ptm.member_id having count(*)>1';
##   
##   #This should return 0 rows. 
##   
##   $sth = $dba->dbc->prepare($sql);
##   
##   # If no duplicate, each select should return an empty row;
##   $sth->execute;
##   
##   $ok = 1;
##   while (my $aref = $sth->fetchrow_arrayref) {
##     my ($member_id) = @$aref;
##     print STDERR "ERROR: some member duplicates (non-singletons) in protein_tree_member!\n";
##     print STDERR "ERROR: USED SQL : $sql\n";
##     $ok = 0;
##     last;
##   }
##   print "PASSED: no member duplicates (non-singletons) in protein_tree_member\n" if ($ok);
##   
## 

# check data consistency between pt_node and homology with node_id
##################################################################

  $sql = "select count(*) from homology h left join protein_tree_node ptn on h.ancestor_node_id=ptn.node_id where ptn.node_id is NULL";
  
  $sth = $dba->dbc->prepare($sql);
  $sth->execute;
  
  while (my $aref = $sth->fetchrow_arrayref) {
    #should be 0
    my ($count) = @$aref;
    if ($count == 0) {
      print "PASSED: homology versus protein_tree_node is consistent\n";
    } else {
      print STDERR "ERROR: homology versus protein_tree_node is NOT consistent\n";
      print STDERR "ERROR: USED SQL : $sql\n";
    }
  }
  
  $sth->finish;

} # end of if ($doit)

# check that one2one genes are not involved in any other orthology
# (one2many or many2many)
# check to be done by method_link_species_set with method_link_type
# ENSEMBL_ORTHOLOGUES
##################################################################

my $mlssa = $dba->get_MethodLinkSpeciesSetAdaptor;
my $mlsses = $mlssa->fetch_all_by_method_link_type('ENSEMBL_ORTHOLOGUES');

if ($doit) {

$sql = "select h.method_link_species_set_id,hm.member_id from homology h, homology_member hm where h.method_link_species_set_id=? and h.homology_id=hm.homology_id group by hm.member_id having count(*)>1 and group_concat(h.description) like '%ortholog_one2one%'";

$sth = $dba->dbc->prepare($sql);

while (my $mlss = shift @$mlsses) {
  # If no mistake in OrthoTree, each select should return an empty row;
  $sth->execute($mlss->dbID);
  my $ok = 1;
  while (my $aref = $sth->fetchrow_arrayref) {
    my ($mlss_id, $member_id) = @$aref;
    print STDERR "ERROR: some [apparent_]one2one_ortholog also one2many or many2many in method_link_species_set_id=$mlss_id!\n";
    print STDERR "ERROR: USED SQL : $sql\n";
    $ok = 0;
    last;
  }
  print "PASSED: [apparent_]one2one_ortholog are ok in method_link_species_set_id=".$mlss->dbID."\n" if ($ok);
}

$sth->finish;
}
# check for homology has no duplicates
######################################

push @{$mlsses},@{$mlssa->fetch_all_by_method_link_type('ENSEMBL_PARALOGUES')};

$sql = "select hm1.member_id,hm2.member_id,h.method_link_species_set_id from homology_member hm1, homology_member hm2, homology h where h.homology_id=hm1.homology_id and hm1.homology_id=hm2.homology_id and hm1.member_id<hm2.member_id and h.method_link_species_set_id=? group by hm1.member_id,hm2.member_id having count(*)>1";

$sth = $dba->dbc->prepare($sql);

while (my $mlss = shift @$mlsses) {
  # If no duplicate, each select should return an empty row;
  $sth->execute($mlss->dbID);
  my $ok = 1;
  while (my $aref = $sth->fetchrow_arrayref) {
    my ($member_id1, $member_id2,$mlss_id) = @$aref;
    print STDERR "ERROR: some homology duplicates in method_link_species_set_id=$mlss_id!\n";
    print STDERR "ERROR: USED SQL : $sql\n";
    $ok = 0;
    last;
  }
  print "PASSED: no homology duplicates in method_link_species_set_id=".$mlss->dbID."\n" if ($ok);
}

$sth->finish;

