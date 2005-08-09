#!/usr/local/ensembl/bin/perl -w

my $description = q{
###########################################################################
##
## PROGRAM LoadUcscNetData.pl
##
## AUTHORS
##    Abel Ureta-Vidal (abel@ebi.ac.uk)
##    Javier Herrero (jherrero@ebi.ac.uk)
##
## COPYRIGHT
##    This script is part of the Ensembl project http://www.ensembl.org
##
## DESCRIPTION
##    This script read BLASTz alignments from a UCSC database and store
##    them in an EnsEMBL Compara database
##
###########################################################################

};

=head1 NAME

LoadUcscNetData.pl

=head1 AUTHORS

 Abel Ureta-Vidal (abel@ebi.ac.uk)
 Javier Herrero (jherrero@ebi.ac.uk)

=head1 COPYRIGHT

This script is part of the Ensembl project http://www.ensembl.org

=head1 DESCRIPTION

This script read BLASTz alignments from a UCSC database and store
them in an EnsEMBL Compara database

=head1 SYNOPSIS

perl LoadUcscNetData.pl
  [--help]                    this menu
   --ucsc_dbname string       (e.g. ucscMm33Rn3) one of the ucsc source database Bio::EnsEMBL::Registry aliases
   --dbname string            (e.g. compara25) one of the compara destination database Bio::EnsEMBL::Registry aliases
   --tName string             (e.g. chr15) one of the chromosome name used by UCSC on their target species (tSpecies)
                              on the base of which alignments will be retrieved
   --tSpecies string          (e.g. mouse) the UCSC target species (i.e. a Bio::EnsEMBL::Registry alias)
                              to which tName refers to
   --qSpecies string          (e.g. Rn3) the UCSC query species (i.e. a Bio::EnsEMBL::Registry alias)
  [--check_length]            check the chromosome length between ucsc and ensembl, then exit
  [--method_link_type string] (e.g. BLASTZ_NET) type of alignment queried (default: BLASTZ_NET)
  [--reg_conf filepath]       the Bio::EnsEMBL::Registry configuration file. If none given, 
                              the one set in ENSEMBL_REGISTRY will be used if defined, if not
                              ~/.ensembl_init will be used.
  [--matrix filepath]         matrix file to be used to score each individual alignment
                              Format should be something like
                              A    C    G    T
                              100 -200  -100 -200
                              -200  100 -200  -100
                              -100 -200  100 -200
                              -200  -100 -200   100
                              O = 2000, E = 50
                              default will choose on the fly the right matrix for the species pair considered.
  [--show_matrix]             Shows the scoring matrix that will be used and exit. Does not start the process
                              loading a compara database. **WARNING** can only be used with the other
                              compulsory arguments
  [--max_gap_size integer]    default: 50
  [start_net_index integer]   default: 0

=head1 UCSC DATABASE TABLES

NB: Part of this information is based on the help pages of the UCSC Genome Browser (http://genome.ucsc.edu/)

=head2 chain[QUERY_SPECIES] or chrXXX_chain[QUERY_SPECIES]

This table contains the coordinates for the chains. Every chain corresponds to an alignment
using a gap scoring system that allows longer gaps than traditional affine gap scoring systems.
It can also tolerate gaps in both species simultaneously. These "double-sided" gaps can be caused by local
inversions and overlapping deletions in both species.

The term "double-sided" gap is used by UCSC in the sense of a separation in both sequences between two
aligned blocks. They can be regarded as double insertions or a non-equivalent region in the alignment.
This will split the alignment while loading it in EnsEMBL (see below).

=head2 chain[QUERY_SPECIES]Link or chrXXX_chain[QUERY_SPECIES]Link

Every chain corresponds to one or several entries in this table. A chain alignment can be decomposed in
several ungapped blocks. Each of these ungapped blocks is stored in this table

=head2 net[QUERY_SPECIES]

A net correspond to the best query/target chain for every part of the target genome. It is useful for finding
orthologous regions and for studying genome rearrangement. Due to the method used to define the nets, some
of them may correspond to a portion of a chain.

=head2 Chromosome specific tables

Depending on the pair of species (query/target), the BLASTz data may be stored in one single table or in
several ones, one per chromosome. The net data are always in one single table though. This script is able
to know by itself whether it needs to access single tables or not.

=head2 Credits for the UCSC BLASTz data

(*) Blastz was developed at Pennsylvania State University by Scott Schwartz, Zheng Zhang, and Webb Miller with advice from Ross Hardison.

(*) Lineage-specific repeats were identified by Arian Smit and his RepeatMasker program.

(*) The axtChain program was developed at the University of California at Santa Cruz by Jim Kent with advice from Webb Miller and David Haussler.

=head2 References for the UCSC data:

(*) Chiaromonte, F., Yap, V.B., Miller, W. Scoring pairwise genomic sequence alignments. Pac Symp Biocomput 2002, 115-26 (2002).

(*) Kent, W.J., Baertsch, R., Hinrichs, A., Miller, W., and Haussler, D. Evolution's cauldron: Duplication, deletion, and rearrangement in the mouse and human genomes. Proc Natl Acad Sci USA 100(20), 11484-11489 (2003).

(*) Schwartz, S., Kent, W.J., Smit, A., Zhang, Z., Baertsch, R., Hardison, R., Haussler, D., and Miller, W. Human-Mouse Alignments with BLASTZ. Genome Res. 13(1), 103-7 (2003).

=head1 LOADING UCSC DATA INTO ENSEMBL

By default, only NET data are stored in EnsEMBL, i.e. the best alignment for every part of
the target genome. Unfortunatelly, GenomicAlignBlocks cannot deal with insertions in both
sequences (this is called "double-sided gaps in the UCSC documentation) and the chain may
be divided in several GenomicAlignBlocks.

If we aim to store nets, as they can be a portion of a chain only,
the chains needs to be trimmed before being stored

=head2 Transforming the coordinates

UCSC stores the alignments as zero-based half-open intervals and uses the reverse-complemented coordinates
for the reverse strand. EnsEMBL always uses inclusive coordinates, starting at 1 and always on the forward
strand. Therefore, some coordinates transformation need to be done.

 For the forward strand:
 - ensembl_start = ucsc_start + 1
 - ensembl_end = ucsc_end

 For the reverse strand:
 - ensembl_start = chromosome_length - ucsc_end + 1
 - ensembl_end = chromosome_length - ucsc_start

=head2 Mapping UCSC random chromosomes

UCSC database cannot cope with non-chromosomic sequence. The pieces of sequence that are not assembled yet
appear in the fake chromosomes called chr1_random, chr2_random, etc. In order to map those alignments into
the EnsEMBL seq_regions, this script uses the assembly data, map the alignments on the right clones and
from them to the corresponding EnsEMBL toplevel seq_region. This process is expected to be quite simple as
no gaps should appear in the alignment because of the mapping.

This feature is only available for genomes with chromosome specific tables!

As no examples of a clone on the reverse strand has been found to date, mapping these alignments if they
fall into a clone on the reverse strand of the random chromosome is not supported at the moment.

=head2 Mapping on EnsEMBL extra assemblies

EnsEMBL might release an extra level of assembly for some low-coverage genomes like the first released cow
genome. In this case this script maps the alignments on the right contigs and from them to the corresponding
genescaffold (or any other toplevel seq_region). This process could be more complex as the EnsEMBL extra
level of assembly may introduce some gaps within the contigs or even cut them.

Mapping an alignment on two different req_regions (if the alignment end up broken in two pieces because of
the new assembly) is not allowed at the moment. The alignment is skipped and a warning message is displayed.

=head1 INTERNAL METHODS

=cut


use strict;
use Getopt::Long;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::Compara::GenomicAlign;
#use Bio::EnsEMBL::Utils::Exception qw(verbose);
#verbose("INFO");


my $ucsc_dbname;
my $dbname;

my $tSpecies;
my $tName;
my $qSpecies;
my $reg_conf;
my $start_net_index = 0;
my $method_link_type = "BLASTZ_NET";
my $max_gap_size = 50;
my $matrix_file;
my $show_matrix_to_be_used = 0;
my $help = 0;
my $check_length = 0;

my $usage = "
$0
  [--help]                    this menu
   --ucsc_dbname string       (e.g. ucscMm33Rn3) one of the ucsc source database Bio::EnsEMBL::Registry aliases
   --dbname string            (e.g. compara25) one of the compara destination database Bio::EnsEMBL::Registry aliases
   --tName string             (e.g. chr15) one of the chromosome name used by UCSC on their target species (tSpecies)
                              on the base of which alignments will be retrieved
   --tSpecies string          (e.g. mouse) the UCSC target species (i.e. a Bio::EnsEMBL::Registry alias)
                              to which tName refers to
   --qSpecies string          (e.g. Rn3) the UCSC query species (i.e. a Bio::EnsEMBL::Registry alias)
  [--check_length]            check the chromosome length between ucsc and ensembl, then exit
  [--method_link_type string] (e.g. BLASTZ_NET) type of alignment queried (default: BLASTZ_NET)
  [--reg_conf filepath]       the Bio::EnsEMBL::Registry configuration file. If none given, 
                              the one set in ENSEMBL_REGISTRY will be used if defined, if not
                              ~/.ensembl_init will be used.
  [--matrix filepath]         matrix file to be used to score each individual alignment
                              Format should be something like
                              A    C    G    T
                              100 -200  -100 -200
                              -200  100 -200  -100
                              -100 -200  100 -200
                              -200  -100 -200   100
                              O = 2000, E = 50
                              default will choose on the fly the right matrix for the species pair considered.
  [--show_matrix]             Shows the scoring matrix that will be used and exit. Does not start the process
                              loading a compara database. **WARNING** can only be used with the other compulsory 
                              arguments
  [--max_gap_size integer]    default: 50
  [start_net_index integer]   default: 0

\n";

GetOptions('help' => \$help,
           'ucsc_dbname=s' => \$ucsc_dbname,
	   'dbname=s' => \$dbname,
           'method_link_type=s' => \$method_link_type,
           'tSpecies=s' => \$tSpecies,
           'tName=s' => \$tName,
           'qSpecies=s' => \$qSpecies,
           'check_length' => \$check_length,
	   'reg_conf=s' => \$reg_conf,
           'start_net_index=i' => \$start_net_index,
           'max_gap_size=i' => \$max_gap_size,
           'matrix=s' => \$matrix_file,
           'show_matrix' => \$show_matrix_to_be_used);

$| = 1;

if ($help) {
  print $usage;
  exit 0;
}

# Take values from ENSEMBL_REGISTRY environment variable or from ~/.ensembl_init
# if no reg_conf file is given.
Bio::EnsEMBL::Registry->load_all($reg_conf);

my $primates_matrix_string = "A C G T
 100 -300 -150 -300
-300  100 -300 -150
-150 -300  100 -300
-300 -150 -300  100
O = 400, E = 30
";

my $mammals_matrix_string = "A C G T
  91 -114  -31 -123
-114  100 -125  -31
 -31 -125  100 -114
-123  -31 -114   91
O = 400, E = 30
";

my $mammals_vs_other_vertebrates_matrix_string = "A C G T
  91  -90  -25 -100
 -90  100 -100  -25
 -25 -100  100  -90
-100  -25  -90   91
O = 400, E = 30
";

my $tight_matrix_string = "A C G T
 100 -200 -100 -200
-200  100 -200 -100
-100 -200  100 -200
-200 -100 -200  100
O = 2000, E = 50
";

my %undefined_combinaisons;
print STDERR $ucsc_dbname,"\n";
my $ucsc_dbc = Bio::EnsEMBL::Registry->get_DBAdaptor($ucsc_dbname, 'compara')->dbc;

my $gdba = Bio::EnsEMBL::Registry->get_adaptor($dbname,'compara','GenomeDB')
    or die "Can't get ($dbname,'compara','GenomeDB')\n";
my $dfa = Bio::EnsEMBL::Registry->get_adaptor($dbname,'compara','DnaFrag')
    or die "Can't get ($dbname,'compara','DnaFrag')\n";
my $gaba = Bio::EnsEMBL::Registry->get_adaptor($dbname,'compara','GenomicAlignBlock')
    or die " Can't get ($dbname,'compara','GenomicAlignBlock')\n";
my $gaga = Bio::EnsEMBL::Registry->get_adaptor($dbname,'compara','GenomicAlignGroup')
    or die " Can't get($dbname,'compara','GenomicAlignGroup')\n";
my $mlssa = Bio::EnsEMBL::Registry->get_adaptor($dbname,'compara','MethodLinkSpeciesSet')
    or die " Can't($dbname,'compara','MethodLinkSpeciesSet')\n";

# cache all tSpecies dnafrag from compara
my $tBinomial = get_binomial_name($tSpecies);
my $tTaxon_id = get_taxon_id($tSpecies);
my $tgdb = $gdba->fetch_by_name_assembly($tBinomial) or die " Can't get fetch_by_name_assembly($tBinomial)\n";
my %tdnafrags;
foreach my $df (@{$dfa->fetch_all_by_GenomeDB_region($tgdb)}) {
  $tdnafrags{$df->name} = $df;
}
# Mitonchondrial chr. is called "M" in UCSC and "MT" in EnsEMBL
$tdnafrags{"M"} = $tdnafrags{"MT"} if (defined $tdnafrags{"MT"});

# cache all qSpecies dnafrag from compara
my $qBinomial = get_binomial_name($qSpecies);
my $qTaxon_id = get_taxon_id($qSpecies);
my $qgdb = $gdba->fetch_by_name_assembly($qBinomial) or die " Can't get fetch_by_name_assembly($qBinomial)\n";
my %qdnafrags;
foreach my $df (@{$dfa->fetch_all_by_GenomeDB_region($qgdb)}) {
  $qdnafrags{$df->name} = $df;
}
# Mitonchondrial chr. is called "M" in UCSC and "MT" in EnsEMBL
$qdnafrags{"M"} = $qdnafrags{"MT"} if (defined $qdnafrags{"MT"});

if ($check_length) {
  check_length(); # Check whether the length of the UCSC and the EnsEMBL chromosome match or not
  exit 0;
}

my $matrix_hash = choose_matrix($matrix_file);
if ($show_matrix_to_be_used) {
  print_matrix($matrix_hash);
  exit 0;
}

# Create and save (if needed) the MethodLinkSpeciesSet
my $mlss = new Bio::EnsEMBL::Compara::MethodLinkSpeciesSet;
$mlss->species_set([$tgdb, $qgdb]);
$mlss->method_link_type($method_link_type);
$mlssa->store($mlss); # Sets the dbID if already exists, creates and sets the dbID if not!

my $chromosome_specific_chain_tables = get_chromosome_specificity_for_tables(
    $ucsc_dbc, $qSpecies, "chain");

#####################################################################
##
## Query to fetch all the nets. The nets are the pieces of chain
## which correspond to the best possible chain for every part of
## the query species
##

my $sql;
my $sth;
if (defined $tName) {
  $sql = "
      SELECT
        bin, level, tName, tStart, tEnd, strand, qName, qStart, qEnd, chainId, ali, score
      FROM net$qSpecies
      WHERE type!=\"gap\" AND tName = \"$tName\"
      ORDER BY tStart, chainId";
} else {
  $sql = "
      SELECT
        bin, level, tName, tStart, tEnd, strand, qName, qStart, qEnd, chainId, ali, score
      FROM net$qSpecies
      WHERE type!=\"gap\"
      ORDER BY tStart, chainId";
}
$sth = $ucsc_dbc->prepare($sql);
$sth->execute();

my ($n_bin,     # ?? [not used]
    $n_level,   # level in genomic_align
    $n_tName,   # name of the target chromosome (e.g. human); used to define the
                # tDnafrag; used to define the chain table name if needed
    $n_tStart,  # start position of this net (0-based); used to restrict the chains
    $n_tEnd,    # end position of this net; used to restrict the chains
    $n_strand,  # strand of this net; + or - [not used]
    $n_qName,   # name of the query chromosome (e.g. cow); used to define the
                # qDnafrag
    $n_qStart,  # start position of this net (0-based, always + strand) [not used]
    $n_qEnd,    # end position of this net (always + strand) [not used]
    $n_chainId, # chain ID; used to fetch chains; group_id in genomic_align_group
    $n_ali,     # ?? [not used]
    $n_score);  # score of the net [not used, we re-score every chain]

$sth->bind_columns
  (\$n_bin, \$n_level, \$n_tName, \$n_tStart, \$n_tEnd, \$n_strand,
   \$n_qName, \$n_qStart, \$n_qEnd, \$n_chainId, \$n_ali, \$n_score);
##
#####################################################################

my $nb_of_net = 0;
my $nb_of_daf_loaded = 0;

my $net_index = 0; # this counter is used to resume the script if needed

my $simple = 0;
my $direct = 0;
my $gapped = 0;
my $complex = 0;
FETCH_NET: while( $sth->fetch() ) {
  $net_index++;
  next if ($net_index < $start_net_index); # $start_net_index is used to resume the script

#   print STDERR "net_index: $net_index, tStart: $n_tStart, chainId: $n_chainId\n";
  $nb_of_net++;
  $n_strand = 1 if ($n_strand eq "+");
  $n_strand = -1 if ($n_strand eq "-");
  $n_tStart++;
  $n_qStart++;

  $n_tName =~ s/^chr//;
  $n_qName =~ s/^chr//;
  $n_qName =~ s/^pt0\-//;

  ###########
  # Check whether the UCSC chromosome has its counterpart in EnsEMBL. Skip otherwise...
  #
  my $tdnafrag = $tdnafrags{$n_tName};
  my $tdnafrag_length;
  my $t_needs_mapping = 0;
  if (!defined $tdnafrag) {
#     print STDERR "daf not stored because $tBinomial seqname ",$n_tName," not in dnafrag table\n";
    my $slice;
    if ($chromosome_specific_chain_tables) {
      $slice = map_random_chromosome($tSpecies, $n_tName, ($n_tStart + 1), $n_tEnd);
    }
    if (!defined($slice)) {
      print STDERR "daf not stored because $tBinomial seqname ",$n_tName,
          " not in dnafrag table\n";
      next FETCH_NET;
    } elsif (!defined($tdnafrags{$slice->seq_region_name})) {
      print STDERR "daf not stored because $tBinomial seqname ",$n_tName, " (", $slice->seq_region_name,
          ") not in dnafrag table\n";
      next FETCH_NET;
    }
    $t_needs_mapping = 1;
    $tdnafrag = $tdnafrags{$n_tName};
#     print STDERR "MAPPING  $tBinomial seqname ",$n_tName, " on ", $slice->seq_region_name,
#         "!!\n";
  } else {
    $tdnafrag_length = $tdnafrag->length();
  }

  my $qdnafrag = $qdnafrags{$n_qName};
  my $qdnafrag_length;
  my $q_needs_mapping = 0;
  if (!defined $qdnafrag) {
    ## The alignment might be defined on a non-toplevel seq_region.
    ## The first EnsEMBL cow assembly released included gene_scaffolds for instance
    ## which were built on top of the original scaffolds.
    my ($slice, $coords, $seq_regions) = map_non_toplevel_seqregion($qSpecies,
        $n_qName, $n_qStart, $n_qEnd, 1);
    if ($slice) {
      foreach my $this_seq_region (@$seq_regions) {
        if (!defined $qdnafrags{$this_seq_region}) {
          print STDERR "daf not stored because $qBinomial seqname ",$n_qName,
              " maps on $this_seq_region and it is not in dnafrag table\n";
          next FETCH_NET;
        }
      }
      $qdnafrag_length = $slice->length();
      $q_needs_mapping = 1;
    } else {
      print STDERR "daf not stored because $qBinomial seqname ",$n_qName," not in dnafrag table\n";
      next FETCH_NET;
    }
  } else {
    $qdnafrag_length = $qdnafrag->length();
  }
  #
  ###########

  my ($c_table, $cl_table); # Name of the tables where chain and chain-links are stored
  if ($chromosome_specific_chain_tables) {
    $c_table = "chr" . $n_tName . "_chain" . $qSpecies;
    $cl_table = "chr" .$n_tName . "_chain" . $qSpecies . "Link";
  } else {
    $c_table = "chain" . $qSpecies;
    $cl_table = "chain" . $qSpecies . "Link";
  }
  # as a chainId seems to be specific to a tName, it should be  no need to add an additional constraint
  # on tName in the sql, but for safe keeping let's add it.
  $sql = "
    SELECT
      c.score, c.tName, c.tSize, c.tStart, c.tEnd, c.qName, c.qSize, c.qStrand, c.qStart, c.qEnd,
      cl.tStart, cl.tEnd, cl.qStart, cl.qStart+cl.tEnd-cl.tStart as qEnd
    FROM $c_table c, $cl_table cl
    WHERE c.id = cl.chainId and cl.chainId = ? and c.tName = cl.tName and c.tName = \"chr$n_tName\"";
  my $sth2 = $ucsc_dbc->prepare($sql);
  $sth2->execute($n_chainId);

  my ($c_score,     # score for this chain [saved in the FeaturePair but overwritten afterwards]
      $c_tName,     # name of the target (e.g. human) chromosome; used here to set
                    # the seqname for the target seq but overwritten afterwards
      $c_tSize,     # size of the target chromosome; used to check if UCSC and EnsEMBL
                    # chrms. length match
      $c_tStart,    # start of the chain in the target chr. [not used]
      $c_tEnd,      # end of the chain in the target chr. [not used]
      $c_qName,     # name of the query (e.g. mouse) chromosome; used here to set
                    # the seqname for the query seq but overwritten afterwards
      $c_qSize,     # size of the target chromosome; used to check if UCSC and EnsEMBL
                    # chr. length match and to reverse the coordinates when needed
      $c_qStrand,   # strand of the query chain; used to know when the coordinates
                    # need to be reversed
      $c_qStart,    # start of the chain in the query chr. [not used]
      $c_qEnd,      # end of the chain in the query chr. [not used]
      $cl_tStart,   # start of the link (ungapped feature) in the target chr.
      $cl_tEnd,     # end of the link in the target chr.
      $cl_qStart,   # startof the link in the query chr.
      $cl_qEnd);    # end of the link in the query chr.

  $sth2->bind_columns(\$c_score,
      \$c_tName,\$c_tSize,\$c_tStart,\$c_tEnd,
      \$c_qName,\$c_qSize,\$c_qStrand,\$c_qStart,\$c_qEnd,
      \$cl_tStart,\$cl_tEnd,\$cl_qStart,\$cl_qEnd);

  my $all_feature_pairs;
  FETCH_CHAIN: while( $sth2->fetch() ) {
    # Checking the chromosome length from UCSC with Ensembl.
    unless (!defined($tdnafrag_length) or $tdnafrag_length == $c_tSize) {
      print STDERR "tSize = $c_tSize for tName = $c_tName and Ensembl has dnafrag",
          " length of $tdnafrag_length\n";
      print STDERR "net_index is $net_index\n";
      exit 2;
    }
    unless ($qdnafrag_length == $c_qSize) {
      print STDERR "qSize = $c_qSize for qName = $c_qName and Ensembl has dnafrag",
          " length of $qdnafrag_length\n";
      print STDERR "net_index is $net_index\n";
      exit 3;
    }
    
    $c_qStrand = 1 if ($c_qStrand eq "+");
    $c_qStrand = -1 if ($c_qStrand eq "-");
    $c_tStart++;
    $c_qStart++;
    $cl_tStart++;
    $cl_qStart++;
    $c_tName =~ s/^chr//;
    $c_qName =~ s/^chr//;
    $c_qName =~ s/^pt0\-//;
    

    if ($c_qStrand < 0) {
      my $length = $cl_qEnd - $cl_qStart;
      $cl_qStart = $c_qSize - $cl_qEnd + 1;
      $cl_qEnd = $cl_qStart + $length;
    }

    if ($t_needs_mapping) {
      my $slice = map_random_chromosome($tSpecies, $c_tName, $cl_tStart, $cl_tEnd);
      next FETCH_CHAIN if (!$slice);
      $c_tName = $slice->seq_region_name;
      $cl_tStart = $slice->start;
      $cl_tEnd = $slice->end;
    }

    if ($q_needs_mapping) {
      my ($slice, $coords, $seq_regions) = map_non_toplevel_seqregion($qSpecies,
        $c_qName, $cl_qStart, $cl_qEnd, $c_qStrand);
      my %seq_regions;
#       print STDERR "$qBinomial $n_qName -> ", join(" - ", @seq_regions), "\n";
      foreach my $seq_region (@$seq_regions) {
        $seq_regions{$seq_region} = 1;
        $qdnafrag = $qdnafrags{$seq_region};
        if (!defined $qdnafrag) {
          print STDERR "daf not stored because $qBinomial seqname ",$n_qName," not in dnafrag table, so not in core\n";
          next FETCH_CHAIN;
        }
      }
      if (scalar(@$coords) == 1) {
        $direct++;
      } else {
        if (scalar(keys %seq_regions) == 1) {
          $gapped++;
#          print STDERR "net_index: $net_index, tStart: $n_tStart, chainId: $n_chainId\n",
#              " $c_qName($seq_regions[0]), $cl_qStart, $cl_qEnd, $c_qStrand\n";
        } else {
          $complex++;
          ## Not supported at the moment!!!
          print STDERR "daf not stored because $qBinomial seqname ",$n_qName," maps on several seq_regions.\n";
          next FETCH_CHAIN;
        }
      }
      my $start = $cl_tStart;
      foreach my $coord (@$coords) {
        if ($coord->isa("Bio::EnsEMBL::Mapper::Coordinate")) {
          my $this_feature_pair = new  Bio::EnsEMBL::FeaturePair(
              -seqname  => $c_tName,
              -start    => $start,
              -end      => $start + $coord->length - 1,
              -strand   => 1,
              -hseqname => shift @$seq_regions,
              -hstart   => $coord->start,
              -hend     => $coord->end,
              -hstrand  => $coord->strand,
              -score    => $c_score);
          push(@$all_feature_pairs, $this_feature_pair);
        }
        $start += $coord->length;
      }
    } else {
      $simple++;
      my $this_feature_pair = new  Bio::EnsEMBL::FeaturePair(
          -seqname  => $c_tName,
          -start    => $cl_tStart,
          -end      => $cl_tEnd,
          -strand   => 1,
          -hseqname  => $c_qName,
          -hstart   => $cl_qStart,
          -hend     => $cl_qEnd,
          -hstrand  => $c_qStrand,
          -score    => $c_score);
      push(@$all_feature_pairs, $this_feature_pair);
    }
  } ### End while loop (FETCH_CHAIN)

  my $dna_align_features = get_DnaAlignFeatures_from_FeaturePairs($all_feature_pairs);

  my @new_dafs;
  while (my $daf = shift @$dna_align_features) {
    my $daf = $daf->restrict_between_positions($n_tStart,$n_tEnd,"SEQ");
    next unless (defined $daf);
    push @new_dafs, $daf;
  }
  next unless (scalar @new_dafs);
#  print STDERR "Loading ",scalar @new_dafs,"...\n";
  
  foreach my $daf (@new_dafs) {
    save_daf_as_genomic_align_block($daf);
  }

  $nb_of_daf_loaded = $nb_of_daf_loaded + scalar @new_dafs;
}

print STDERR "simple = $simple; direct = $direct; gapped = $gapped and complex = $complex\n";
print STDERR "nb_of_net: ", $nb_of_net,"\n";
print STDERR "nb_of_daf_loaded: ", $nb_of_daf_loaded,"\n";

print STDERR "Here is a statistic summary of nucleotides matching not defined in the scoring matrix used\n";
foreach my $key (sort {$a cmp $b} keys %undefined_combinaisons) {
  print STDERR $key," ",$undefined_combinaisons{$key},"\n";
}

$sth->finish;

print STDERR "\n";

exit();


=head2 get_binomial_name

  Arg[1]     : string $species_name
  Example    : $human_binomial_name = get_binomial_name("human");
  Description: This method get the binomial name from the core database.
               It takes a Registry alias as an input and return the
               binomial name for that species.
  Returntype : string

=cut

sub get_binomial_name {
  my ($species) = @_;
  my $binomial_name;

  my $meta_container_adaptor = Bio::EnsEMBL::Registry->get_adaptor($species, 'core', 'MetaContainer');
  if (!defined($meta_container_adaptor)) {
    die("Cannot get the MetaContainerAdaptor for species <$species>\n");
  }
  $binomial_name = $meta_container_adaptor->get_Species->binomial;
  if (!$binomial_name) {
    die("Cannot get the binomial name for species <$species>\n");
  }

  return $binomial_name;
}


=head2 get_taxon_id

  Arg[1]     : string $species_name
  Example    : $human_taxon_id = get_taxon_id("human");
  Description: This method get the taxon ID from the core database.
               It takes a Registry alias as an input and return the
               taxon ID for that species.
  Returntype : int

=cut

sub get_taxon_id {
  my ($species) = @_;
  my $taxon_id;

  my $meta_container_adaptor = Bio::EnsEMBL::Registry->get_adaptor($species, 'core', 'MetaContainer');
  if (!defined($meta_container_adaptor)) {
    die("Cannot get the MetaContainerAdaptor for species <$species>\n");
  }
  $taxon_id = $meta_container_adaptor->get_taxonomy_id;
  if (!$taxon_id) {
    die("Cannot get the taxon ID for species <$species>\n");
  }

  return $taxon_id;
}


=head2 get_chromosome_specificity_for_tables

  Arg[1]     : Bio::EnsEMBL::DBSQL::DBConnection $ucsc_compara_dbc
  Arg[2]     : string $species_name
  Arg[3]     : string $type ("chain" or "net")
  Example    : $chromosome_specific_chain_table =
                 get_chromosome_specificity_for_tables($ucsc_compara_dbc,
                 "hg17", "chain");
  Description: UCSC database may contain a pair of tables for all the
               chromosomes or a pair per chromosome depending on the species.
               This method tests whether the tables are chromosome
               specific or not
  Returntype : boolean

=cut

sub get_chromosome_specificity_for_tables {
  my ($ucsc_dbc, $species, $type) = @_;
  my $chromosome_specific_chain_tables = 1;
  
  $type = "chain" unless (defined($type) and $type eq "net");
  
  my $sql = "show tables like '$type$species\%'";
  $sth = $ucsc_dbc->prepare($sql);
  $sth->execute;
  
  my ($table_name);
  
  $sth->bind_columns(\$table_name);
  
  my $table_count = 0;
  
  while( $sth->fetch() ) {
    if ($table_name eq "$type$species") {
      $table_count++;
    }
    if ($table_name eq $type.$species."Link") {
      $table_count++;
    }
  }
  $sth->finish;

  $chromosome_specific_chain_tables = 0 if ($table_count == 2);
  
  return $chromosome_specific_chain_tables;
}


=head2 map_random_chromosome

  Arg[1]     : string $species_name
  Arg[2]     : string $seq_region_name
  Arg[3]     : int $start (inclusive coordinates)
  Arg[4]     : int $end (inclusive coordinates)
  Example    :
  Description: This method tries to match the EnsEMBL Slice corresponding
               to the piece of UCSC random chromosome. The UCSC random
               chromosomes are a hack used to refer to non-chromosome level
               sequences in the UCSC genome DB.
  Returntype : Bio::EnsEMBL::Slice object

=cut

sub map_random_chromosome {
  my ($species_name, $seq_region_name, $start, $end) = @_;

  my ($chrom_start, $chrom_end, $frag_name, $frag_start, $frag_end, $frag_strand);

  if ($seq_region_name =~ /_random$/) {
    ## Get mapping information from goldenpath table
    my $random_sql = "SELECT chrom, chromStart, chromEnd, frag, fragStart, fragEnd, strand".
    " FROM chr${seq_region_name}_gold where chromStart <= ? and chromEnd >= ?";
    my $random_sth = $ucsc_dbc->prepare($random_sql);
    $random_sth->execute($end, $start - 1);
    my $all_data = $random_sth->fetchall_arrayref;
    return undef if (scalar(@$all_data) != 1);

    $chrom_start = $all_data->[0]->[1];
    $chrom_end = $all_data->[0]->[2];
    $frag_name = $all_data->[0]->[3];
    $frag_start = $all_data->[0]->[4];
    $frag_end = $all_data->[0]->[5];
    $frag_strand = $all_data->[0]->[6];
  } else {
    return undef;
  }

  my ($slice_start, $slice_end, $slice_strand);
  if ($frag_strand eq "+") {
    $slice_start = $start - $chrom_start + $frag_start;
    $slice_end = $end - $chrom_start + $frag_start;
  } else {
    print STDERR "random chromosome maps on a reversed fragent. Not supported at the moment!\n";
    return undef;
  }

  my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor($species_name, "core", "Slice");
  my $slice = $slice_adaptor->fetch_by_region(undef, $frag_name, $slice_start, $slice_end);
  if (!defined($slice)) {
    ## Fake slice. Used to give a more useful warning message!
    $slice = new Bio::EnsEMBL::Slice(
          -seq_region_name => $frag_name,
          -start => $frag_start,
          -end => $frag_end,
          -strand => ($frag_strand eq "+")?1:-1,
          -coord_system => new Bio::EnsEMBL::CoordSystem(-name => "unknown", -rank => 100),
      );
    return $slice;
  }

  my $projections = $slice->project("toplevel");
  if (@$projections != 1) {
    return $slice;
  }

  return $projections->[0]->to_Slice;
}


=head2 map_non_toplevel_seqregion

  Arg[1]     : string $species_name
  Arg[2]     : string $seq_region_name
  Arg[3]     : int $start
  Arg[4]     : int $end
  Arg[4]     : int $strand
  Example    :
  Description: This method tries to map UCSC coordinates on toplevel
               EnsEMBL seq_regions. This is needed when EnsEMBL provides
               an extra level of assembly like in the case of the first
               release of the cow genome.
  Returntype : listref of Bio::EnsEMBL::Coordinate or Bio::EnsEMBL::Gap
               objects and a listref of strings

=cut

sub map_non_toplevel_seqregion {
  my ($species_name, $seq_region_name, $start, $end, $strand) = @_;

  my $coord_system_adaptor = Bio::EnsEMBL::Registry->get_adaptor(
      $species_name, "core", "CoordSystem");
  return (undef, undef, undef) if (!$coord_system_adaptor);
  my $other_coord_system;
  
  my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor($species_name, "core", "Slice");
  my $slice;
  if ($seq_region_name =~ /^SCAFFOLD/i) {
    $slice = $slice_adaptor->fetch_by_region("scaffold", $seq_region_name);
    $other_coord_system = $coord_system_adaptor->fetch_by_name("scaffold");
  }
  return (undef, undef, undef) if (!$slice or !$other_coord_system);

  my $assembly_mapper_adaptor = Bio::EnsEMBL::Registry->get_adaptor(
      $species_name, "core", "AssemblyMapper");
  my $toplevel_coord_system = $coord_system_adaptor->fetch_by_name("toplevel");
  my $assembly_mapper = $assembly_mapper_adaptor->fetch_by_CoordSystems(
      $other_coord_system, $toplevel_coord_system);

  my @coords = $assembly_mapper->map($slice->seq_region_name,
      $start, $end, $strand, $other_coord_system);
  my @seq_regions = $assembly_mapper->list_seq_regions($slice->seq_region_name,
      $start, $end, $other_coord_system);

  return ($slice, \@coords, \@seq_regions);
}


=head2 get_DnaAlignFeatures_from_FeaturePairs

  Arg[1]     : arrayref of Bio::EnsEMBL::FeaturePair objects
  Example    :
  Description: transform a set of Bio::EnsEMBL::FeaturePair objects
               into a set of Bio::EnsEMBL::DnaDnaAlignFeature objects
               made of compatible Bio::EnsEMBL::FeaturePair objects
  Returntype : arrayref of Bio::EnsEMBL::DnaDnaAlignFeature objects

=cut

sub get_DnaAlignFeatures_from_FeaturePairs {
  my ($all_feature_pairs) = @_;
  my $dna_align_features;

  my $these_feature_pairs = [];
  my ($previous_t_end, $previous_q_seqname, $previous_q_start, $previous_q_end);
  foreach my $this_feature_pair (@$all_feature_pairs) {
    my $t_start = $this_feature_pair->start;
    my $t_end = $this_feature_pair->end;
    my $q_seqname = $this_feature_pair->hseqname;
    my $q_start = $this_feature_pair->hstart;
    my $q_end = $this_feature_pair->hend;
    my $q_strand = $this_feature_pair->hstrand;
    
    unless (defined $previous_t_end && defined $previous_q_end) {
      $previous_t_end = $t_end;
      $previous_q_seqname = $q_seqname;
      $previous_q_start = $q_start;
      $previous_q_end = $q_end;
      push @$these_feature_pairs, $this_feature_pair;
      next;
    }

    if (
      # if target seqname changed (may happen because of the mapping)
      ($q_seqname ne $previous_q_seqname) or

      # if there are insertions in both sequences (non-equivalent regions)
      (($t_start - $previous_t_end > 1) && 
      (($q_strand > 0 && $q_start - $previous_q_end > 1) ||
      ($q_strand < 0 && $previous_q_start - $q_end > 1))) or

      # if gap is larger that $max_gap_size in target seq
      ($t_start - $previous_t_end > $max_gap_size) or

      # if gap is larger that $max_gap_size in query seq
      (($q_strand > 0 && $q_start - $previous_q_end > $max_gap_size) ||
      ($q_strand < 0 && $previous_q_start - $q_end > $max_gap_size))
        ) {
      my $this_dna_align_feature = new Bio::EnsEMBL::DnaDnaAlignFeature(
          -features => \@$these_feature_pairs);
      $these_feature_pairs = [];
      $this_dna_align_feature->group_id($n_chainId);
      $this_dna_align_feature->level_id(($n_level + 1)/2);
      push @$dna_align_features, $this_dna_align_feature;
    }
    $previous_t_end = $t_end;
    $previous_q_start = $q_start;
    $previous_q_end = $q_end;
    push @$these_feature_pairs, $this_feature_pair;
  }
  if (@$these_feature_pairs) {
    my $this_dna_align_feature = new Bio::EnsEMBL::DnaDnaAlignFeature(
        -features => \@$these_feature_pairs);
    $these_feature_pairs = [];
    $this_dna_align_feature->group_id($n_chainId);
    $this_dna_align_feature->level_id(($n_level + 1)/2);
    push @$dna_align_features, $this_dna_align_feature;
  }

  return $dna_align_features;
}


=head2 save_daf_as_genomic_align_block

  Arg[1]     : Bio::EnsEMBL::DnaDnaAlignFeature $daf
  Example    : save_daf_as_genomic_align_block($daf)
  Description: 
  Returntype : -none-

=cut

sub save_daf_as_genomic_align_block {
  my ($daf) = @_;
    
  # Get cigar_lines and length of the alignment from the daf object
  my ($tcigar_line, $qcigar_line, $length) = parse_daf_cigar_line($daf);

  # Create GenomicAlign for target sequence
  my $tga = new Bio::EnsEMBL::Compara::GenomicAlign;
  $tga->dnafrag($tdnafrags{$daf->seqname});
  $tga->dnafrag_start($daf->start);
  $tga->dnafrag_end($daf->end);
  $tga->dnafrag_strand($daf->strand);
  $tga->cigar_line($tcigar_line);
  $tga->level_id($daf->level_id);

  # Create GenomicAlign for query sequence
  my $qga = new Bio::EnsEMBL::Compara::GenomicAlign;
  $qga->dnafrag($qdnafrags{$daf->hseqname});
  $qga->dnafrag_start($daf->hstart);
  $qga->dnafrag_end($daf->hend);
  $qga->dnafrag_strand($daf->hstrand);
  $qga->cigar_line($qcigar_line);
  $qga->level_id($daf->level_id);

  # Create the GenomicAlignBlock
  my $gab = new Bio::EnsEMBL::Compara::GenomicAlignBlock;
  $gab->method_link_species_set($mlss);

  # Re-score the GenomicAlignBlock (previous score was for the whole net)
  my ($score, $percent_id) = score_and_identity($qga->aligned_sequence,
      $tga->aligned_sequence, $matrix_hash);
  $gab->score($score);
  $gab->perc_id($percent_id);
  $gab->length($length);
  $gab->genomic_align_array([$tga, $qga]);

  # Create the GenomicAlignGroup
  my $gag = new Bio::EnsEMBL::Compara::GenomicAlignGroup;
  $gag->dbID($daf->group_id);
  $gag->type("default");
  $gag->genomic_align_array([$tga, $qga]);

  $gaba->store($gab); # This stores the Bio::EnsEMBL::Compara::GenomicAlign objects
  $gaga->store($gag);
}

=head2 parse_daf_cigar_line

  Arg[1]     : 
  Example    : 
  Description: 
  Returntype : 

=cut

sub parse_daf_cigar_line {
  my ($daf) = @_;
  my ($cigar_line, $hcigar_line, $length);

  my @pieces = split(/(\d*[DIMG])/, $daf->cigar_string);

  my $counter = 0;
  my $hcounter = 0;
  foreach my $piece ( @pieces ) {
    next if ($piece !~ /^(\d*)([MDI])$/);
    
    my $num = ($1 or 1);
    my $type = $2;
    
    if( $type eq "M" ) {
      $counter += $num;
      $hcounter += $num;
      
    } elsif( $type eq "D" ) {
      $cigar_line .= (($counter == 1) ? "" : $counter)."M";
      $counter = 0;
      $cigar_line .= (($num == 1) ? "" : $num)."D";
      $hcounter += $num;
      
    } elsif( $type eq "I" ) {
      $counter += $num;
      $hcigar_line .= (($hcounter == 1) ? "" : $hcounter)."M";
      $hcounter = 0;
      $hcigar_line .= (($num == 1) ? "" : $num)."D";
    }
    $length += $num;
  }
  $cigar_line .= (($counter == 1) ? "" : $counter)."M"
    if ($counter);
  $hcigar_line .= (($hcounter == 1) ? "" : $hcounter)."M"
    if ($hcounter);
  
  return ($cigar_line, $hcigar_line, $length);
}


=head2 choose_matrix

  Arg[1]     : string $matrix_filename
  Example    : $matrix_hash = choose_matrix();
  Example    : $matrix_hash = choose_matrix("this_matrix.txt");
  Description: reads the matrix from the file provided or get the right matrix
               depending on the pair of species.
  Returntype : ref. to a hash

=cut

sub choose_matrix {
  my ($matrix_file) = @_;
  my $matrix_hash;

  if ($matrix_file) {
    my $matrix_string = "";
    open M, $matrix_file ||
      die "Can not open $matrix_file file\n";
    while (<M>) {
      next if (/^\s*$/);
      $matrix_string .= $_;
    }
    close M;
    $matrix_hash = get_matrix_hash($matrix_string);
    print STDERR "Using customed scoring matrix from $matrix_file file\n";
#     print STDERR "\n$matrix_string\n";
  
  } elsif ( grep(/^$tTaxon_id$/, (9606, 9598)) &&
      grep(/^$qTaxon_id$/, (9606, 9598)) ) {
    $matrix_hash = get_matrix_hash($primates_matrix_string);
    print STDERR "Using primates scoring matrix\n";
#     print STDERR "\n$primates_matrix_string\n";
  
  } elsif ( grep(/^$tTaxon_id$/, (9606, 10090, 10116, 9598, 9615, 9913)) &&
            grep(/^$qTaxon_id$/, (9606, 10090, 10116, 9598, 9615, 9913)) ) {
    $matrix_hash = get_matrix_hash($mammals_matrix_string);
    print STDERR "Using mammals scoring matrix\n";
#     print STDERR "\n$mammals_matrix_string\n";
  
  } elsif ( (grep(/^$tTaxon_id$/, (9606, 10090, 10116, 9598, 9615, 9913, 9031)) &&
            grep(/^$qTaxon_id$/, (31033, 7955, 9031, 99883, 8364)))
            ||
            (grep(/^$qTaxon_id$/, (9606, 10090, 10116, 9598, 9615, 9913, 9031)) &&
            grep(/^$tTaxon_id$/, (31033, 7955, 9031, 99883, 8364)))) {
    $matrix_hash = get_matrix_hash($mammals_vs_other_vertebrates_matrix_string);
    print STDERR "Using mammals_vs_other_vertebrates scoring matrix\n";
#     print STDERR "\n$mammals_vs_other_vertebrates_matrix_string\n";
  
  } else {
    die "taxon_id undefined or matrix not set up for this pair of species $tTaxon_id, $qTaxon_id)\n";
  }

  return $matrix_hash;
}

=head2 get_matrix_hash

  Arg[1]     : string $matrix_string
  Example    : $matrix_hash = get_matrix_hash($matrix_string);
  Description: transform the matrix string into a hash
  Returntype : ref. to a hash

=cut

sub get_matrix_hash {
  my ($matrix_string) = @_;
  
  my %matrix_hash;

  my @lines = split /\n/, $matrix_string;
  my @letters = split /\s+/, shift @lines;

  foreach my $letter (@letters) {
    my $line = shift @lines;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    my @penalties = split /\s+/, $line;
    die "Size of letters array and penalties array are different\n"
        unless (scalar @letters == scalar @penalties);
    for (my $i=0; $i < scalar @letters; $i++) {
      $matrix_hash{uc $letter}{uc $letters[$i]} = $penalties[$i];
      $matrix_hash{uc $letters[$i]}{uc $letter} = $penalties[$i];
    }
  }
  while (my $line = shift @lines) {
    if ($line =~ /^\s*O\s*=\s*(\d+)\s*,\s*E\s*=\s*(\d+)\s*$/) {
      my $gap_opening_penalty = $1;
      my $gap_extension_penalty = $2;

      $gap_opening_penalty *= -1 if ($gap_opening_penalty > 0);
      $matrix_hash{'gap_opening_penalty'} = $gap_opening_penalty;

      $gap_extension_penalty *= -1 if ($gap_extension_penalty > 0);
      $matrix_hash{'gap_extension_penalty'} = $gap_extension_penalty;
    }
  }

  return \%matrix_hash;
}


=head2 print_matrix

  Arg[1]     : hashref $matix_hash 
  Example    : print_matrix($matrix_hash)
  Description: print the weight matrix to the STDERR
  Returntype : -none-

=cut

sub print_matrix {
  my ($matrix_hash) = @_;

  print STDERR "Here is the matrix hash structure\n";
  foreach my $key1 (sort {$a cmp $b} keys %{$matrix_hash}) {
    if ($key1 =~ /[ACGT]+/) {
      print STDERR "$key1 :";
      foreach my $key2 (sort {$a cmp $b} keys %{$matrix_hash->{$key1}}) {
        printf STDERR "   $key2 %5d",$matrix_hash->{$key1}{$key2};
      }
      print STDERR "\n";
    } else {
      print STDERR $key1," : ",$matrix_hash->{$key1},"\n";
    }
  }
  print STDERR "\n";
}


=head2 score_and_identity

  Arg[1]     : 
  Example    : 
  Description: 
  Returntype : 

=cut

sub score_and_identity {
  my ($qy_seq, $tg_seq, $matrix_hash) = @_;

  my $length = length($qy_seq);

  unless (length($tg_seq) == $length) {
    warn "qy sequence length ($length bp) and tg sequence length (".length($tg_seq)." bp)".
        " should be identical\nExit 1\n";
    exit 1;
  }

  my @qy_seq_array = split //, $qy_seq;
  my @tg_seq_array = split //, $tg_seq;

  my $score = 0;
  my $number_identity = 0;
  my $opened_gap = 0;
  for (my $i=0; $i < $length; $i++) {
    if ($qy_seq_array[$i] eq "-" || $tg_seq_array[$i] eq "-") {
      if ($opened_gap) {
        $score += $matrix_hash->{'gap_extension_penalty'};
      } else {
        $score += $matrix_hash->{'gap_opening_penalty'};
        $opened_gap = 1;
      }
    } else {
      # maybe check for N letter here
      if (uc $qy_seq_array[$i] eq uc $tg_seq_array[$i]) {
        $number_identity++;
      }
      unless (defined $matrix_hash->{uc $qy_seq_array[$i]}{uc $tg_seq_array[$i]}) {
        unless (defined $undefined_combinaisons{uc $qy_seq_array[$i] . ":" . uc $tg_seq_array[$i]}) {
          $undefined_combinaisons{uc $qy_seq_array[$i] . ":" . uc $tg_seq_array[$i]} = 1;
        } else {
          $undefined_combinaisons{uc $qy_seq_array[$i] . ":" . uc $tg_seq_array[$i]}++;
        }
#        print STDERR uc $qy_seq_array[$i],":",uc $tg_seq_array[$i]," combination not defined in the matrix\n";
      } else {
        $score += $matrix_hash->{uc $qy_seq_array[$i]}{uc $tg_seq_array[$i]};
      }
      $opened_gap = 0;
    }
  }

  return ($score, int($number_identity/$length*100));
}


=head2 check_length

  Arg[1]     : 
  Example    : 
  Description: 
  Returntype : 

=cut

sub check_length {

  my $sql = "show tables like '"."%"."chain$qSpecies'";
  my $sth = $ucsc_dbc->prepare($sql);
  $sth->execute();

  my ($table);
  $sth->bind_columns(\$table);
  
  my (%tNames,%qNames);
  
  while( $sth->fetch() ) {
    $sql = "select tName,tSize from $table group by tName,tSize";
    
    my $sth2 = $ucsc_dbc->prepare($sql);
    $sth2->execute();
    
    my ($tName,$tSize);
    
    $sth2->bind_columns(\$tName,\$tSize);

    while( $sth2->fetch() ) {
      $tName =~ s/^chr//;
      $tNames{$tName} = $tSize;
    }
    $sth2->finish;

    $sql = "select qName,qSize from $table group by qName,qSize";

    $sth2 = $ucsc_dbc->prepare($sql);
    $sth2->execute();

    my ($qName,$qSize);
    
    $sth2->bind_columns(\$qName,\$qSize);

    while( $sth2->fetch() ) {
      $qName =~ s/^chr//;
      $qNames{$qName} = $qSize;
    }
    $sth2->finish;
  }

  $sth->finish;

  # Checking the chromosome length from UCSC with Ensembl.
  foreach my $tName (keys %tNames) {
    my $tdnafrag = $tdnafrags{$tName};
    next unless (defined $tdnafrag);
    unless ($tdnafrag->length == $tNames{$tName}) {
      print STDERR "tSize = " . $tNames{$tName} ." for tName = $tName and Ensembl has dnafrag length of ",$tdnafrag->length . "\n";
    }
  }
  # Checking the chromosome length from UCSC with Ensembl.
  foreach my $qName (keys %qNames) {
    my $qdnafrag = $qdnafrags{$qName};
    next unless (defined $qdnafrag);
    unless ($qdnafrag->length == $qNames{$qName}) {
      print STDERR "qSize = " . $qNames{$qName} ." for qName = $qName and Ensembl has dnafrag length of ",$qdnafrag->length . "\n";
    }
  }
}

