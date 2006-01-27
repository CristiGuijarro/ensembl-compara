#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Compara::GenomeDB;
use Bio::EnsEMBL::Compara::MethodLinkSpeciesSet;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Hive;
use Bio::EnsEMBL::DBLoader;
use Bio::EnsEMBL::Registry;

Bio::EnsEMBL::Registry->no_version_check(1);

srand();

my $conf_file;
my %hive_params ;
my $verbose;
my $help;

my %compara_conf;
$compara_conf{'-port'} = 3306;
my %chain_conf;
my %net_conf;

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};


GetOptions('help'     => \$help,
           'conf=s'   => \$conf_file,
           'v' => \$verbose);

if ($help) { usage(); }

$self->parse_conf($conf_file);


unless(defined($compara_conf{'-host'}) and defined($compara_conf{'-user'}) and defined($compara_conf{'-dbname'})) {
  print "\nERROR : must specify host, user, and database to connect to compara\n\n";
  usage(); 
}

$self->{'comparaDBA'}   = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(%compara_conf);
$self->{'hiveDBA'}      = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(-DBCONN => $self->{'comparaDBA'}->dbc);

if(%hive_params) {
  if(defined($hive_params{'hive_output_dir'})) {
    die("\nERROR!! hive_output_dir doesn't exist, can't configure\n  ", $hive_params{'hive_output_dir'} , "\n")
      unless(-d $hive_params{'hive_output_dir'});
    $self->{'comparaDBA'}->get_MetaContainer->delete_key('hive_output_dir');
    $self->{'comparaDBA'}->get_MetaContainer->store_key_value('hive_output_dir', $hive_params{'hive_output_dir'});
  }
}


$self->prepareChainSystem;

foreach my $dnaCollectionConf (@{$self->{'dna_collection_conf_list'}}) {
  print("creating ChunkAndGroup jobs\n");
  $self->storeMaskingOptions($dnaCollectionConf);
  $self->createChunkAndGroupDnaJobs($dnaCollectionConf);
}

$self->create_dump_nib_job($chain_conf{'query_collection_name'});
$self->create_dump_nib_job($chain_conf{'target_collection_name'});
$self->prepCreateAlignmentChainsJobs;

foreach my $netConf (@{$self->{'net_conf_list'}}) {
  print("prepChunkGroupJob\n");
  $self->prepareNetSystem($netConf);
}

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "loadGenomicAlignSystem.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -conf <path>           : config file describing compara, templates\n";
  print "loadGenomicAlignSystem.pl v1.1\n";
  
  exit(1);  
}


sub parse_conf {
  my $self = shift;
  my $conf_file = shift;

  $self->{'chunk_group_conf_list'} = [];
  $self->{'chunkCollectionHash'} = {};
  
  if($conf_file and (-e $conf_file)) {
    #read configuration file from disk
    my @conf_list = @{do $conf_file};

    foreach my $confPtr (@conf_list) {
      my $type = $confPtr->{TYPE};
      delete $confPtr->{TYPE};
      print("HANDLE type $type\n") if($verbose);
      if($type eq 'COMPARA') {
        %compara_conf = %{$confPtr};
      }
      elsif($type eq 'HIVE') {
        %hive_params = %{$confPtr};
      }
      elsif($type eq 'DNA_COLLECTION') {
        push @{$self->{'dna_collection_conf_list'}} , $confPtr;
      }
      elsif($type eq 'CHAIN_CONFIG') {
        %chain_conf = %{$confPtr};
      }
      elsif($type eq 'NET_CONFIG') {
        push @{$self->{'net_conf_list'}} , $confPtr;
#        %net_conf = %{$confPtr};
      }

    }
  }
}


#
# need to make sure analysis 'SubmitGenome' is in database
# this is a generic analysis of type 'genome_db_id'
# the input_id for this analysis will be a genome_db_id
# the full information to access the genome will be in the compara database
# also creates 'GenomeLoadMembers' analysis and
# 'GenomeDumpFasta' analysis in the 'genome_db_id' chain
sub prepareChainSystem
{
  #yes this should be done with a config file and a loop, but...
  my $self = shift;

  my $dataflowRuleDBA = $self->{'hiveDBA'}->get_DataflowRuleAdaptor;
  my $ctrlRuleDBA = $self->{'hiveDBA'}->get_AnalysisCtrlRuleAdaptor;
  my $stats;

  #
  # creating ChunkAndGroupDna analysis
  #
  my $chunkAndGroupDnaAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'ChunkAndGroupDna',
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::ChunkAndGroupDna',
      -parameters      => ""
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($chunkAndGroupDnaAnalysis);
  $stats = $chunkAndGroupDnaAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(-1); #unlimited
  $stats->update();
  $self->{'chunkAndGroupDnaAnalysis'} = $chunkAndGroupDnaAnalysis;
  #
  # DumpLargeNibForChains Analysis
  #
  my $dumpLargeNibForChainsAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'DumpLargeNibForChains',
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::DumpLargeNibForChains',
      -parameters      => ""
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($dumpLargeNibForChainsAnalysis);
  $stats = $dumpLargeNibForChainsAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(1);
  $stats->update();
  $self->{'dumpLargeNibForChainsAnalysis'} = $dumpLargeNibForChainsAnalysis;

  $ctrlRuleDBA->create_rule($chunkAndGroupDnaAnalysis, $dumpLargeNibForChainsAnalysis);

  #
  # createAlignmentChainsJobs Analysis
  #
  my $sql = "INSERT ignore into method_link SET method_link_id=?, type=?";
  my $sth = $self->{'comparaDBA'}->dbc->prepare($sql);
  my ($input_method_link_id, $input_method_link_type) = @{$chain_conf{'input_method_link'}};
  $sth->execute($input_method_link_id, $input_method_link_type);
  my ($output_method_link_id, $output_method_link_type) = @{$chain_conf{'output_method_link'}};
  $sth->execute($output_method_link_id, $output_method_link_type);
  $sth->finish;

  my $parameters = "{\'method_link\'=>\'$input_method_link_type\'}";

  my $createAlignmentChainsJobsAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'CreateAlignmentChainsJobs',
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::CreateAlignmentChainsJobs',
      -parameters      => $parameters
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($createAlignmentChainsJobsAnalysis);
  $stats = $createAlignmentChainsJobsAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(1);
  $stats->update();
  $self->{'createAlignmentChainsJobsAnalysis'} = $createAlignmentChainsJobsAnalysis;

  $ctrlRuleDBA->create_rule($dumpLargeNibForChainsAnalysis, $createAlignmentChainsJobsAnalysis);

  #
  # AlignmentChains Analysis
  #
  my $max_gap = $chain_conf{'max_gap'};
  my $output_group_type = $chain_conf{'output_group_type'};
  $group_type = "chain" unless (defined $group_type);
  $parameters = "{\'input_method_link\'=>\'$input_method_link_type\',\'output_method_link\'=>\'$output_method_link_type\',\'max_gap\'=>\'$max_gap\','output_group_type\'=>\'$group_type\'}";
  my $alignmentChainsAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'AlignmentChains',
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::AlignmentChains',
      -parameters      => $parameters
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($alignmentChainsAnalysis);
  $stats = $alignmentChainsAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(10);
  $stats->update();
  $self->{'alignmentChainsAnalysis'} = $alignmentChainsAnalysis;

  $ctrlRuleDBA->create_rule($createAlignmentChainsJobsAnalysis, $alignmentChainsAnalysis);

  #
  # creating UpdateMaxAlignmentLengthAfterChain analysis
  #
  
  my $updateMaxAlignmentLengthAfterChainAnalysis = Bio::EnsEMBL::Analysis->new
    (-db_version      => '1',
     -logic_name      => 'UpdateMaxAlignmentLengthAfterChain',
     -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::UpdateMaxAlignmentLength',
     -parameters      => "");
  
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($updateMaxAlignmentLengthAfterChainAnalysis);
  $stats = $updateMaxAlignmentLengthAfterChainAnalysis->stats;
  $stats->hive_capacity(1);
  $stats->update();
  $self->{'updateMaxAlignmentLengthAfterChainAnalysis'} = $updateMaxAlignmentLengthAfterChainAnalysis;
  
  
  #
  # create UpdateMaxAlignmentLengthAfterChain job
  #
  my $input_id = 1;
  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
      (-input_id       => $input_id,
       -analysis       => $self->{'updateMaxAlignmentLengthAfterChainAnalysis'});

  $ctrlRuleDBA->create_rule($alignmentChainsAnalysis, $self->{'updateMaxAlignmentLengthAfterChainAnalysis'});
}

sub prepareNetSystem {
  my $self = shift;
  my $netConf = shift;

  return unless($netConf);

  my $dataflowRuleDBA = $self->{'hiveDBA'}->get_DataflowRuleAdaptor;
  my $ctrlRuleDBA = $self->{'hiveDBA'}->get_AnalysisCtrlRuleAdaptor;
  my $stats;


  #
  # createAlignmentNetsJobs Analysis
  #
  my $sql = "INSERT ignore into method_link SET method_link_id=?, type=?";
  my $sth = $self->{'comparaDBA'}->dbc->prepare($sql);
  my ($input_method_link_id, $input_method_link_type) = @{$netConf->{'input_method_link'}};
  $sth->execute($input_method_link_id, $input_method_link_type);
  my ($output_method_link_id, $output_method_link_type) = @{$netConf->{'output_method_link'}};
  $sth->execute($output_method_link_id, $output_method_link_type);
  $sth->finish;

  my $createAlignmentNetsJobsAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'CreateAlignmentNetsJobs',
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::CreateAlignmentNetsJobs',
      -parameters      => ""
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($createAlignmentNetsJobsAnalysis);
  $stats = $createAlignmentNetsJobsAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(1);
  $stats->update();
  $self->{'createAlignmentNetsJobsAnalysis'} = $createAlignmentNetsJobsAnalysis;

  $ctrlRuleDBA->create_rule($self->{'alignmentChainsAnalysis'}, $createAlignmentNetsJobsAnalysis);

  my $hexkey = sprintf("%x", rand(time()));
  print("hexkey = $hexkey\n");

  #
  # AlignmentNets Analysis
  #
  my $max_gap = $netConf->{'max_gap'};
  my $input_group_type = $netConf->{'input_group_type'};
  $input_group_type = "chain" unless (defined $input_group_type);
  my $output_group_type = $netConf->{'output_group_type'};
  $output_group_type = "default" unless (defined $output_group_type);
  my $parameters = "{\'input_method_link\'=>\'$input_method_link_type\',\'output_method_link\'=>\'$output_method_link_type\',\'max_gap\'=>\'$max_gap\','input_group_type\'=>\'$input_group_type\','output_group_type\'=>\'$output_group_type\'}";
  my $alignmentNetsAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'AlignmentNets-'.$hexkey,
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::AlignmentNets',
      -parameters      => $parameters
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($alignmentNetsAnalysis);
  $stats = $alignmentNetsAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(10);
  $stats->update();
  $self->{'alignmentNetsAnalysis'} = $alignmentNetsAnalysis;

  $ctrlRuleDBA->create_rule($createAlignmentNetsJobsAnalysis, $alignmentNetsAnalysis);

  $self->prepCreateAlignmentNetsJobs($netConf,$alignmentNetsAnalysis->logic_name);

  unless (defined $self->{'updateMaxAlignmentLengthAfterNetAnalysis'}) {

    #
    # creating UpdateMaxAlignmentLengthAfterNet analysis
    #

    my $updateMaxAlignmentLengthAfterNetAnalysis = Bio::EnsEMBL::Analysis->new
      (-db_version      => '1',
       -logic_name      => 'UpdateMaxAlignmentLengthAfterNet',
       -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::UpdateMaxAlignmentLength',
       -parameters      => "");

    $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($updateMaxAlignmentLengthAfterNetAnalysis);
    my $stats = $updateMaxAlignmentLengthAfterNetAnalysis->stats;
    $stats->hive_capacity(1);
    $stats->update();
    $self->{'updateMaxAlignmentLengthAfterNetAnalysis'} = $updateMaxAlignmentLengthAfterNetAnalysis;

    #
    # create UpdateMaxAlignmentLengthAfterNet job
    #
    my $input_id = 1;
    Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
        (-input_id       => $input_id,
         -analysis       => $self->{'updateMaxAlignmentLengthAfterNetAnalysis'});
  }

  $ctrlRuleDBA->create_rule($alignmentNetsAnalysis,$self->{'updateMaxAlignmentLengthAfterNetAnalysis'});

}
sub storeMaskingOptions
{
  my $self = shift;
  my $dnaCollectionConf = shift;

  my $masking_options_file = $dnaCollectionConf->{'masking_options_file'};
  if (defined $masking_options_file && ! -e $masking_options_file) {
    print("\n__ERROR__\n");
    print("masking_options_file $masking_options_file does not exist\n");
    exit(5);
  }

  my $options_hash_ref;
  if (defined $masking_options_file) {
    $options_hash_ref = do($masking_options_file);
  } else {
    $options_hash_ref = $dnaCollectionConf->{'masking_options'};
  }

  return unless($options_hash_ref);

  my @keys = keys %{$options_hash_ref};
  my $options_string = "{\n";
  foreach my $key (@keys) {
    $options_string .= "'$key'=>'" . $options_hash_ref->{$key} . "',\n";
  }
  $options_string .= "}";

  $dnaCollectionConf->{'masking_analysis_data_id'} =
    $self->{'hiveDBA'}->get_AnalysisDataAdaptor->store_if_needed($options_string);

  $dnaCollectionConf->{'masking_options'} = undef;
}


sub createChunkAndGroupDnaJobs
{
  my $self = shift;
  my $dnaCollectionConf = shift;

  if($dnaCollectionConf->{'collection_name'}) {
    my $collection_name = $dnaCollectionConf->{'collection_name'};
    $self->{'chunkCollectionHash'}->{$collection_name} = $dnaCollectionConf;
  }

  my $input_id = "{";
  my @keys = keys %{$dnaCollectionConf};
  foreach my $key (@keys) {
    next unless(defined($dnaCollectionConf->{$key}));
    print("    ",$key," : ", $dnaCollectionConf->{$key}, "\n");
    $input_id .= "'$key'=>'" . $dnaCollectionConf->{$key} . "',";
  }
  $input_id .= "}";

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
      (-input_id       => $input_id,
       -analysis       => $self->{'chunkAndGroupDnaAnalysis'},
       -input_job_id   => 0);
}

sub create_dump_nib_job
{
  my $self = shift;
  my $collection_name = shift;
  
  my $input_id = "{\'dna_collection_name\'=>\'$collection_name\'}";

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
        -input_id       => $input_id,
        -analysis       => $self->{'dumpLargeNibForChainsAnalysis'},
        -input_job_id   => 0
        );
  
}

sub prepCreateAlignmentChainsJobs {
  my $self = shift;

  my $query_collection_name = $chain_conf{'query_collection_name'};
  my $target_collection_name = $chain_conf{'target_collection_name'};
  my $gdb_id1 = $self->{'chunkCollectionHash'}->{$query_collection_name}->{'genome_db_id'};
  my $gdb_id2 = $self->{'chunkCollectionHash'}->{$target_collection_name}->{'genome_db_id'};

  my $input_id = "{\'query_genome_db_id\'=>\'$gdb_id1\',\'target_genome_db_id\'=>\'$gdb_id2\',";
  $input_id .= "\'query_collection_name\'=>\'$query_collection_name\',\'target_collection_name\'=>\'$target_collection_name\'}";

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
        -input_id       => $input_id,
        -analysis       => $self->{'createAlignmentChainsJobsAnalysis'},
        -input_job_id   => 0
        );
}

sub prepCreateAlignmentNetsJobs {
  my $self = shift;
  my $netConf = shift;
  my $logic_name = shift;

  return unless($netConf);

  my $input_group_type = $netConf->{'input_group_type'};
  $input_group_type = "chain" unless (defined $input_group_type);

  my $query_collection_name = $netConf->{'query_collection_name'};
  my $target_collection_name = $netConf->{'target_collection_name'};
  my $gdb_id1 = $self->{'chunkCollectionHash'}->{$query_collection_name}->{'genome_db_id'};
  my $gdb_id2 = $self->{'chunkCollectionHash'}->{$target_collection_name}->{'genome_db_id'};
  my ($input_method_link_id, $input_method_link_type) = @{$netConf->{'input_method_link'}};

  my $input_id = "{\'method_link\'=>\'$input_method_link_type\'";
  $input_id .= ",\'query_genome_db_id\'=>\'$gdb_id1\',\'target_genome_db_id\'=>\'$gdb_id2\',";
  $input_id .= "\'collection_name\'=>\'$query_collection_name\'";
  $input_id .= ",\'logic_name\'=>\'$logic_name\'";
  $input_id .= ",\'group_type\'=>\'$input_group_type\'}";

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
        -input_id       => $input_id,
        -analysis       => $self->{'createAlignmentNetsJobsAnalysis'},
        -input_job_id   => 0
        );
}

1;

