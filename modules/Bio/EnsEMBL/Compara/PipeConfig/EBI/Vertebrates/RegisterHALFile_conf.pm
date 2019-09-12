=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::EBI::Vertebrates::RegisterHALFile_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::EBI::Vertebrates::RegisterHALFile_conf -mlss_id <mlss_id> -species_name_mapping "{134 => 'C57B6J', 155 => 'rn6',160 => '129S1_SvImJ',161 => 'A_J',162 => 'BALB_cJ',163 => 'C3H_HeJ',164 => 'C57BL_6NJ',165 => 'CAST_EiJ',166 => 'CBA_J',167 => 'DBA_2J',168 => 'FVB_NJ',169 => 'LP_J',170 => 'NOD_ShiLtJ',171 => 'NZO_HlLtJ',172 => 'PWK_PhJ',173 => 'WSB_EiJ',174 => 'SPRET_EiJ', 178 => 'AKR_J'}"

=head1 DESCRIPTION

Mini-pipeline to load the species-tree and the chromosome-name mapping from a HAL file

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::EBI::Vertebrates::RegisterHALFile_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::PipeConfig::RegisterHALFile_conf');

sub default_options {
    my ($self) = @_;
    return {
        %{$self->SUPER::default_options},

        'master_db'             => 'compara_master',

        'division'              => 'vertebrates',
    };
}


1;
