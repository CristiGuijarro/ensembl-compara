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

srand();

my $conf_file;
my $verbose;
my $help;

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};


GetOptions('help'     => \$help,
           'conf=s'   => \$conf_file,
           'v' => \$verbose);

if ($help) { usage(); }

my %hive_params;
my %compara_conf;
$compara_conf{'-port'} = 3306;

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


$self->preparePairAlignerSystem;

foreach my $dnaCollectionConf (@{$self->{'dna_collection_conf_list'}}) {
  print("creating ChunkAndGroup jobs\n");
  $self->storeMaskingOptions($dnaCollectionConf);
  $self->createChunkAndGroupDnaJobs($dnaCollectionConf);
}

foreach my $pairAlignerConf (@{$self->{'pair_aligner_conf_list'}}) {
  print("creating PairAligner analysis\n");
  $self->createPairAlignerAnalysis($pairAlignerConf);
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
  print "loadPairAlignerSystem.pl v1.1\n";
  
  exit(1);  
}


sub parse_conf {
  my $self = shift;
  my $conf_file = shift;

  $self->{'genomic_align_conf_list'} = [];
  $self->{'dna_collection_conf_list'} = [];
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
      elsif($type eq 'PAIR_ALIGNER') {
        push @{$self->{'pair_aligner_conf_list'}} , $confPtr;
      }
      elsif($type eq 'DNA_COLLECTION') {
        push @{$self->{'dna_collection_conf_list'}} , $confPtr;
      }
    }
  }
}


# need to make sure analysis 'SubmitGenome' is in database
# this is a generic analysis of type 'genome_db_id'
# the input_id for this analysis will be a genome_db_id
# the full information to access the genome will be in the compara database
# also creates 'GenomeLoadMembers' analysis and
# 'GenomeDumpFasta' analysis in the 'genome_db_id' chain
sub preparePairAlignerSystem
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
  # creating CreatePairAlignerJobs analysis
  #
  my $createPairAlignerJobsAnalysis = Bio::EnsEMBL::Analysis->new(
      -db_version      => '1',
      -logic_name      => 'CreatePairAlignerJobs',
      -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::CreatePairAlignerJobs',
      -parameters      => ""
    );
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($createPairAlignerJobsAnalysis);
  $stats = $createPairAlignerJobsAnalysis->stats;
  $stats->batch_size(1);
  $stats->hive_capacity(1);
  $stats->update();
  $self->{'createPairAlignerJobsAnalysis'} = $createPairAlignerJobsAnalysis;

  $ctrlRuleDBA->create_rule($chunkAndGroupDnaAnalysis, $createPairAlignerJobsAnalysis);

}

sub createPairAlignerAnalysis
{
  my $self        = shift;
  my $pair_aligner_conf  = shift;  #hash reference

  my $dataflowRuleDBA = $self->{'hiveDBA'}->get_DataflowRuleAdaptor;
  my $ctrlRuleDBA = $self->{'hiveDBA'}->get_AnalysisCtrlRuleAdaptor;

  print("creating PairAligner jobs\n") if($verbose);
  my $query_dnaCollectionConf = $self->{'chunkCollectionHash'}->{$pair_aligner_conf->{'query_collection_name'}};
  my $target_dnaCollectionConf = $self->{'chunkCollectionHash'}->{$pair_aligner_conf->{'target_collection_name'}};

  if($pair_aligner_conf->{'method_link'}) {
    my ($method_link_id, $method_link_type) = @{$pair_aligner_conf->{'method_link'}};
    my $sql = "INSERT ignore into method_link SET method_link_id=$method_link_id, type='$method_link_type'";
    print("$sql\n");
    $self->{'hiveDBA'}->dbc->do($sql);
        
    #
    # creating MethodLinkSpeciesSet entry
    #
    my $mlss = new Bio::EnsEMBL::Compara::MethodLinkSpeciesSet;
    $mlss->method_link_type($method_link_type); 
    my $gdb_id1 = $query_dnaCollectionConf->{'genome_db_id'};
    my $gdb_id2 = $target_dnaCollectionConf->{'genome_db_id'};
    printf("create MethodLinkSpeciesSet for genomes %d:%d\n", $gdb_id1, $gdb_id2);
    my $gdb1 = $self->{'comparaDBA'}->get_GenomeDBAdaptor->fetch_by_dbID($gdb_id1);
    unless (defined $gdb1) {
      print("\n__ERROR__\n");
      print("There is no genomeDB for genome_db_id $gdb_id1\n");
      print("You need to load the genomeDBs first, with comparaLoadGenomes.pl \n");
      exit(2);
    }
    my $gdb2 = $self->{'comparaDBA'}->get_GenomeDBAdaptor->fetch_by_dbID($gdb_id2);
    unless (defined $gdb2) {
      print("\n__ERROR__\n");
      print("There is no genomeDB for genome_db_id $gdb_id2\n");
      print("You need to load the genomeDBs first, with comparaLoadGenomes.pl \n");
      exit(3);
    }
    $mlss->species_set([$gdb1, $gdb2]);
    $self->{'comparaDBA'}->get_MethodLinkSpeciesSetAdaptor->store($mlss);
    $self->{'method_link_species_set'} = $mlss;
    $pair_aligner_conf->{'method_link_species_set_id'} = $mlss->dbID;
  }
      
  my $hexkey = sprintf("%x", rand(time()));
  print("hexkey = $hexkey\n");

  #
  # creating PairAligner_$hexkey analysis
  #

  my $pairAlignerAnalysis = new Bio::EnsEMBL::Analysis(%{$pair_aligner_conf->{'analysis_template'}});
  my $logic_name = "PairAligner-".$hexkey;
  $logic_name = $pair_aligner_conf->{'logic_name_prefix'}."-".$hexkey
    if (defined $pair_aligner_conf->{'logic_name_prefix'});

  print "logic_name $logic_name\n";
  $pairAlignerAnalysis->logic_name($logic_name);
  $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($pairAlignerAnalysis);
  my $stats = $pairAlignerAnalysis->stats;
  $stats->hive_capacity(200);
  if($pair_aligner_conf->{'max_parallel_workers'}) {
    print "max_parallel_workers: ",$pair_aligner_conf->{'max_parallel_workers'},"\n";
    $stats->hive_capacity($pair_aligner_conf->{'max_parallel_workers'});
  }
  print "hive_capacity: ", $stats->hive_capacity,"\n";
  if($pair_aligner_conf->{'batch_size'}) {
    $stats->batch_size($pair_aligner_conf->{'batch_size'});
  }
  $stats->update();

  unless (defined $self->{'updateMaxAlignmentLengthBeforeFDAnalysis'}) {

    #
    # creating UpdateMaxAlignmentLengthBeforeFD analysis
    #

    my $updateMaxAlignmentLengthBeforeFDAnalysis = Bio::EnsEMBL::Analysis->new
      (-db_version      => '1',
       -logic_name      => 'UpdateMaxAlignmentLengthBeforeFD',
       -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::UpdateMaxAlignmentLength',
       -parameters      => "");
    
    $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($updateMaxAlignmentLengthBeforeFDAnalysis);
    my $stats = $updateMaxAlignmentLengthBeforeFDAnalysis->stats;
    $stats->hive_capacity(1);
    $stats->update();
    $self->{'updateMaxAlignmentLengthBeforeFDAnalysis'} = $updateMaxAlignmentLengthBeforeFDAnalysis;


    #
    # create UpdateMaxAlignmentLengthBeforeFD job
    #
    my $input_id = 1;
    Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
        (-input_id       => $input_id,
         -analysis       => $self->{'updateMaxAlignmentLengthBeforeFDAnalysis'});
  }

  $ctrlRuleDBA->create_rule($pairAlignerAnalysis, $self->{'updateMaxAlignmentLengthBeforeFDAnalysis'});

  #
  # create CreatePairAlignerJobs job
  #
  my $input_id = "{'pair_aligner'=>'" . $pairAlignerAnalysis->logic_name . "'";
  $input_id .= ",'query_collection_name'=>'" .
    $pair_aligner_conf->{'query_collection_name'}  . "'";
  $input_id .= ",'target_collection_name'=>'" .
    $pair_aligner_conf->{'target_collection_name'} . "'";
  $input_id .= ",'method_link_species_set_id'=>" .
    $pair_aligner_conf->{'method_link_species_set_id'}
    if(defined($pair_aligner_conf->{'method_link_species_set_id'}));
  $input_id .= "}";

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
      (-input_id       => $input_id,
       -analysis       => $self->{'createPairAlignerJobsAnalysis'});


  

  # creating FilterDuplicates analysis
  #
  if ($pair_aligner_conf->{'filter_duplicates_options'}) {
    unless ($pair_aligner_conf->{'filter_duplicates_options'} eq "all" ||
            $pair_aligner_conf->{'filter_duplicates_options'} eq "in_chunk_overlaps") {
      print("filter_duplicates_options entry can only be \'all\' or \'in_chunk_overlaps\', not \'".$pair_aligner_conf->{'filter_duplicates_options'}."\'\n");
      exit(4);
    }
    my $queryFilterDuplicatesAnalysis;
    unless ($pair_aligner_conf->{'filter_duplicates_options'} eq "in_chunk_overlaps" &&
            (! defined $query_dnaCollectionConf->{'overlap'} ||
             $query_dnaCollectionConf->{'overlap'} == 0)) {
      #
      # creating QueryFilterDuplicates analysis
      #
      my $parameters = "{'method_link_species_set_id'=>".$pair_aligner_conf->{'method_link_species_set_id'};
      $parameters .= ",'chunk_size'=>".$query_dnaCollectionConf->{'chunk_size'};
      $parameters .= ",'overlap'=>".$query_dnaCollectionConf->{'overlap'};
      $parameters .= ",'options'=>'".$pair_aligner_conf->{'filter_duplicates_options'}."'}";

      $queryFilterDuplicatesAnalysis = Bio::EnsEMBL::Analysis->new
        (-db_version      => '1',
         -logic_name      => 'QueryFilterDuplicates-'.$hexkey,
         -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::FilterDuplicates',
         -parameters      => $parameters);
      $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($queryFilterDuplicatesAnalysis);
      $stats = $queryFilterDuplicatesAnalysis->stats;
      $stats->batch_size(1);
      $stats->hive_capacity(-1); #unlimited
      $stats->status('BLOCKED');
      $stats->update();
      $self->{'queryFilterDuplicatesAnalysis'} = $queryFilterDuplicatesAnalysis;

      $ctrlRuleDBA->create_rule($self->{'updateMaxAlignmentLengthBeforeFDAnalysis'}, $queryFilterDuplicatesAnalysis);

      unless (defined $self->{'updateMaxAlignmentLengthAfterFDAnalysis'}) {
        
        #
        # creating UpdateMaxAlignmentLengthAfterFD analysis
        #
        
        my $updateMaxAlignmentLengthAfterFDAnalysis = Bio::EnsEMBL::Analysis->new
          (-db_version      => '1',
           -logic_name      => 'UpdateMaxAlignmentLengthAfterFD',
           -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::UpdateMaxAlignmentLength',
           -parameters      => "");
        
        $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($updateMaxAlignmentLengthAfterFDAnalysis);
        my $stats = $updateMaxAlignmentLengthAfterFDAnalysis->stats;
        $stats->hive_capacity(1);
        $stats->update();
        $self->{'updateMaxAlignmentLengthAfterFDAnalysis'} = $updateMaxAlignmentLengthAfterFDAnalysis;
        

        #
        # create UpdateMaxAlignmentLengthAfterFD job
        #
        my $input_id = 1;
        Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
            (-input_id       => $input_id,
             -analysis       => $self->{'updateMaxAlignmentLengthAfterFDAnalysis'});
      }
      
      $ctrlRuleDBA->create_rule($queryFilterDuplicatesAnalysis,$self->{'updateMaxAlignmentLengthAfterFDAnalysis'},);

      #
      # create CreateFilterDuplicatesJobs analysis
      #
      unless (defined $self->{'createFilterDuplicatesJobsAnalysis'}) {
        my $createFilterDuplicatesJobsAnalysis = Bio::EnsEMBL::Analysis->new
          (-db_version      => '1',
           -logic_name      => 'CreateFilterDuplicatesJobs',
           -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::CreateFilterDuplicatesJobs',
           -parameters      => "");
        $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($createFilterDuplicatesJobsAnalysis);
        $stats = $createFilterDuplicatesJobsAnalysis->stats;
        $stats->batch_size(1);
        if($pair_aligner_conf->{'max_parallel_workers'}) {
          $stats->hive_capacity($pair_aligner_conf->{'max_parallel_workers'});
        }
        $stats->update();
        $self->{'createFilterDuplicatesJobsAnalysis'} = $createFilterDuplicatesJobsAnalysis;

        $ctrlRuleDBA->create_rule($self->{'chunkAndGroupDnaAnalysis'}, $createFilterDuplicatesJobsAnalysis);
      }

      #
      # create QueryCreateFilterDuplicatesJobs job
      #
      my $input_id .= "{'logic_name'=>'".$queryFilterDuplicatesAnalysis->logic_name ."'";
      $input_id .= ",'collection_name'=>'".$pair_aligner_conf->{'query_collection_name'} ."'";
      if ($query_dnaCollectionConf->{'region'}) {
        $input_id .= ",'region'=>'".$query_dnaCollectionConf->{'region'}."'"
      }
      $input_id .= "}";

      Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
          (-input_id       => $input_id,
           -analysis       => $self->{'createFilterDuplicatesJobsAnalysis'});
    }

    unless ($pair_aligner_conf->{'filter_duplicates_options'} eq "all" ||
            ($pair_aligner_conf->{'filter_duplicates_options'} eq "in_chunk_overlaps" &&
            (! defined $target_dnaCollectionConf->{'overlap'} ||
             $target_dnaCollectionConf->{'overlap'} == 0))) {
      #
      # creating TargetFilterDuplicates analysis
      #
      my $parameters = "{'method_link_species_set_id'=>".$pair_aligner_conf->{'method_link_species_set_id'};
      $parameters .= ",'chunk_size'=>".$target_dnaCollectionConf->{'chunk_size'};
      $parameters .= ",'overlap'=>".$target_dnaCollectionConf->{'overlap'};
      $parameters .= ",'options'=>'".$pair_aligner_conf->{'filter_duplicates_options'}."'}";

      my $targetFilterDuplicatesAnalysis = Bio::EnsEMBL::Analysis->new
        (-db_version      => '1',
         -logic_name      => 'TargetFilterDuplicates-'.$hexkey,
         -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::FilterDuplicates',
         -parameters      => $parameters);
      $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($targetFilterDuplicatesAnalysis);
      $stats = $targetFilterDuplicatesAnalysis->stats;
      $stats->batch_size(1);
      $stats->hive_capacity(-1); #unlimited
      $stats->status('BLOCKED');
      $stats->update();
      $self->{'targetFilterDuplicatesAnalysis'} = $targetFilterDuplicatesAnalysis;

      if (defined $queryFilterDuplicatesAnalysis) {
        $ctrlRuleDBA->create_rule($queryFilterDuplicatesAnalysis, $targetFilterDuplicatesAnalysis);
      } else {
        $ctrlRuleDBA->create_rule($pairAlignerAnalysis, $targetFilterDuplicatesAnalysis);
      }

      unless (defined $self->{'updateMaxAlignmentLengthAfterFDAnalysis'}) {
        
        #
        # creating UpdateMaxAlignmentLengthAfterFD analysis
        #
        
        my $updateMaxAlignmentLengthAfterFDAnalysis = Bio::EnsEMBL::Analysis->new
          (-db_version      => '1',
           -logic_name      => 'UpdateMaxAlignmentLengthAfterFD',
           -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::UpdateMaxAlignmentLength',
           -parameters      => "");
        
        $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($updateMaxAlignmentLengthAfterFDAnalysis);
        my $stats = $updateMaxAlignmentLengthAfterFDAnalysis->stats;
        $stats->hive_capacity(1);
        $stats->update();
        $self->{'updateMaxAlignmentLengthAfterFDAnalysis'} = $updateMaxAlignmentLengthAfterFDAnalysis;
        

        #
        # create UpdateMaxAlignmentLengthAfterFD job
        #
        my $input_id = 1;
        Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
            (-input_id       => $input_id,
             -analysis       => $self->{'updateMaxAlignmentLengthAfterFDAnalysis'});
      }
      
      $ctrlRuleDBA->create_rule($targetFilterDuplicatesAnalysis,$self->{'updateMaxAlignmentLengthAfterFDAnalysis'},);

      #
      # create CreateFilterDuplicatesJobs analysis
      #
      unless (defined $self->{'createFilterDuplicatesJobsAnalysis'}) {
        my $createFilterDuplicatesJobsAnalysis = Bio::EnsEMBL::Analysis->new
          (-db_version      => '1',
           -logic_name      => 'CreateFilterDuplicatesJobs',
           -module          => 'Bio::EnsEMBL::Compara::Production::GenomicAlignBlock::CreateFilterDuplicatesJobs',
           -parameters      => "");
        $self->{'hiveDBA'}->get_AnalysisAdaptor()->store($createFilterDuplicatesJobsAnalysis);
        $stats = $createFilterDuplicatesJobsAnalysis->stats;
        $stats->batch_size(1);
        if($pair_aligner_conf->{'max_parallel_workers'}) {
          $stats->hive_capacity($pair_aligner_conf->{'max_parallel_workers'});
        }
        $stats->update();
        $self->{'createFilterDuplicatesJobsAnalysis'} = $createFilterDuplicatesJobsAnalysis;

        $ctrlRuleDBA->create_rule($self->{'chunkAndGroupDnaAnalysis'}, $createFilterDuplicatesJobsAnalysis);
      }
      #
      # create TargetCreateFilterDuplicatesJobs job
      #
      my $input_id .= "{'logic_name'=>'".$targetFilterDuplicatesAnalysis->logic_name ."'";
      $input_id .= ",'collection_name'=>'".$pair_aligner_conf->{'target_collection_name'}."'";
      if ($target_dnaCollectionConf->{'region'}) {
        $input_id .= ",'region'=>'".$target_dnaCollectionConf->{'region'}."'"
      }
      $input_id .= "}";

      Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob
          (-input_id       => $input_id,
           -analysis       => $self->{'createFilterDuplicatesJobsAnalysis'});
    }
  }
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

1;

