package Bio::EnsEMBL::Compara::DnaDnaAlignFeature;

# EnsEMBL module for storing dna-dna pairwise alignments
#
# Cared for by Michele Clamp <michele@sanger.ac.uk>
#
# You may distribute this module under the same terms as perl itself
#

=head1 NAME

  Bio::EnsEMBL::Compara::DnaDnaAlignFeature - Ensembl specific dna-dna pairwise alignment feature

=head1 SYNOPSIS

    my $feat = new Bio::EnsEMBL::Compara::DnaDnaAlignFeature(-seqname => 'myseq',
						    -start   => 100,
						    -end     => 120,
						    -strand  => 1,
						    -hstart  => 200,
						    -hend    => 220,
						    -analysis    => $analysis,
						    -cigar_string => '100,200,3:110,210,11');

Alternatively if you have an array of ungapped features

    my $feat = new Bio::EnsEMBL::Compara::DnaDnaAlignFeature(-features => \@features);

Where @features is an array of Bio::EnsEMBL::FeaturePair

There is a method to manipulate the cigar_string into ungapped features

    my @ungapped_features = $feat->ungapped_features;

This converts the cigar string into an array of Bio::EnsEMBL::FeaturePair

$analysis is a Bio::EnsEMBL::Analysis object

Bio::EnsEMBL::SeqFeature methods can be used
Bio::EnsEMBL::FeaturePair methods can be used

The cigar_string contains the ungapped pieces that make up the gapped alignment

It is format is qstart,qend,length*strand.

So in the above example the gapped alignment contains 2 ungapped pieces from

    100-102 in the query and 200-202 in the hit and
    110-120 in the query and 210-220 in the hit.

The length parts of the cigar string are positive as the strand is +ve.


To make things clearer this is how a blast HSP would be parsed

    >AK014066
           Length = 146

      Minus Strand HSPs:

      Score = 76 (26.8 bits), Expect = 1.4, P = 0.74
      Identities = 20/71 (28%), Positives = 29/71 (40%), Frame = -1

    Query:   479 GLQAPPPTPQGCRLIPPPPLGLQAPLPTLRAVGSSHHHP*GRQGSSLSSFRSSLASKASA 300
                 G  APPP PQG R   P P G + P   L             + + ++  R  +A   +
    Sbjct:     7 GALAPPPAPQG-RWAFPRPTG-KRPATPLHGTARQDRQVRRSEAAKVTGCRGRVAPHVAP 64

    Query:   299 SSPHNPSPLPS 267
                    H P+P P+
    Sbjct:    65 PLTHTPTPTPT 75

The alignment goes from 267 to 479 in sequence 1 and 7 to 75 in sequence 2 and the
strand is -1.

The alignment is made up of the following ungapped pieces :

    sequence 1 start 447 , sequence 2 start 7  , match length 33 , strand -1
    sequence 1 start 417 , sequence 2 start 18 , match length 27 , strand -1
    sequence 1 start 267 , sequence 2 start 27 , match length 137 , strand -1

These ungapped pieces are made up into the following string (called a cigar string)

    447,7,-33:417,18,-27:267,27,-137

i.e. seqstart1,seqstart2,length: etc


=cut 


use Bio::EnsEMBL::Compara::BaseAlignFeature;


use vars qw(@ISA);
use strict;

@ISA = qw( Bio::EnsEMBL::Compara::BaseAlignFeature );



=head2 _parse_cigar

    Arg      : None.  

    Usage    : Internal method - not used.

    Function : Converts the cigar_string contained by the module into 
               an array of ungapped Bio::EnsEMBL::FeaturePair.

               See sub cigar_string for an explanation of what that is.

    Exception: If no cigar_string is returned from $self->cigar_string but
               this should never happen as $self->cigar_string should throw 
               it first.

               If the cigar string is the wrong format.

               If the length of an ungapped piece is 0

    Caller   : Called internally to the module by ungapped_features

=cut


sub _parse_cigar {
  my ($self) = @_;
  return $self->_generic_parse_cigar( 1, 1 );
}

      
=head2 _parse_features

    Arg      : Array of Bio::EnsEMBL::FeaturePair

    Usage    : Internal method - not used.

    Function : Converts an array of FeaturePairs into a gapped feature with
               a cigar string describing the 

               See sub cigar_string for an explanation of what that is.

    Exception: If the argument passed is not an array reference

               All the features must have arisen from the same source
               i.e. a blast HSP or some other alignment.  Thus
               exceptions are thrown when the scores,percent ids,p_values
               seqnames , hseqnames and strands differ amongst the input 
               features.

               All the features must not overlap in order to provide a 
               sane gapped alignment.  An exception is thrown if they do.

               If any element of the array is not a Bio::EnsEMBL::FeaturePair

               If there are no elements in the array

               If the hit length is not equal to the query length

    Caller   : Called internally to the module by the constructor

=cut

sub _parse_features {
  my ($self,$features) = @_;

  $self->_generic_parse_features( $features, 1, 1 );
}

=head2 restrict_between_positions

    Arg      : start_position (integer),end_position (integer), 'seqname' or 'hseqname' (string)

    Usage    : $self->restrict_between_positions(2305,145000,'seqname')

    Function : Take a DnaDnaAlignFeature object ($self) and return a new DnaDnaAlignFeature object
               with recalculated (if needed) ungapped features which are in between or overlapping
               start_position and end_position. The third argument ('seqname' or 'hseqname') informs 
               which sequence the start_position and end_position refer to.
               Return undef if the new DnaDnaAlignFeature object do not contain any ungapped features.
    Exception: If arguments are not defined or not of the expected type

    Caller   : No specific caller.

=cut

sub restrict_between_positions {
  my ($self,$start,$end,$seqref) = @_;
  
  unless (defined $start && $start =~ /^\d+$/) {
    $self->throw("The first argument is not defined or is not an integer");
  }
  unless (defined $end && $end =~ /^\d+$/) {
    $self->throw("The second argument is not defined or is not an integer");
  }
  unless (defined $seqref && 
	  ($seqref eq "seqname" || $seqref eq "hseqname")) {
    $self->throw("The third argument is not defined or is not equal to 'seqname' or 'hseqname'");
  }

  my ($start_method1,$end_method1,$strand_method1,$start_method2,$end_method2,$strand_method2) =
    qw(start end strand hstart hend hstrand);

  if ($seqref eq "hseqname") {
    ($start_method1,$end_method1,$strand_method1,$start_method2,$end_method2,$strand_method2) =
    qw(hstart hend hstrand start end strand);
  }
  
  my @restricted_features;
  
  foreach my $ungapped_feature ($self->ungapped_features) {

    if ($ungapped_feature->$start_method1() > $end ||
	$ungapped_feature->$end_method1() < $start) {
      
      next;
      
    } elsif ($ungapped_feature->$end_method1() <= $end &&
	     $ungapped_feature->$start_method1() >= $start) {
      
      push @restricted_features, $ungapped_feature;
      
    } else {
      
      if ($ungapped_feature->$strand_method1() eq $ungapped_feature->$strand_method2()) {

	if ($ungapped_feature->$start_method1() < $start) {
	  
	  my $offset = $start - $ungapped_feature->$start_method1();
	  $ungapped_feature->$start_method1($start);
	  $ungapped_feature->$start_method2($ungapped_feature->$start_method2() + $offset);
	  
	}
	if ($ungapped_feature->$end_method1() > $end) {
	  
	  my $offset = $ungapped_feature->$end_method1() - $end;
	  $ungapped_feature->$end_method1($end);
	  $ungapped_feature->$end_method2($ungapped_feature->$end_method2() - $offset);
	  
	}
      } else {
	
	if ($ungapped_feature->$start_method1() < $start) {
	  
	  my $offset = $start - $ungapped_feature->$start_method1();
	  $ungapped_feature->$start_method1($start);
	  $ungapped_feature->$end_method2($ungapped_feature->$end_method2() - $offset);
	  
	}
	if ($ungapped_feature->$end_method1() > $end) {
	  
	  my $offset = $ungapped_feature->$end_method1() - $end;
	  $ungapped_feature->$end_method1($end);
	  $ungapped_feature->$start_method2($ungapped_feature->$start_method2() + $offset);
	  
	}
      }
      
      push @restricted_features, $ungapped_feature;
      
    }
  }

  if (scalar @restricted_features) {
    my $DnaDnaAlignFeature = new Bio::EnsEMBL::Compara::DnaDnaAlignFeature('-features' =>\@restricted_features);
    return $DnaDnaAlignFeature;
  } else {
    return undef;
  }
}

1;
