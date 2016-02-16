# Copyright © (2011) Institut national de l'information
#                    géographique et forestière 
# 
# Géoportail SAV <geop_services@geoportail.fr>
# 
# This software is a computer program whose purpose is to publish geographic
# data using OGC WMS and WMTS protocol.
# 
# This software is governed by the CeCILL-C license under French law and
# abiding by the rules of distribution of free software.  You can  use, 
# modify and/ or redistribute the software under the terms of the CeCILL-C
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info". 
# 
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability. 
# 
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or 
# data to be ensured and,  more generally, to use and operate it in the 
# same conditions as regards security. 
# 
# The fact that you are presently reading this means that you have had
# 
# knowledge of the CeCILL-C license and that you accept its terms.

################################################################################

=begin nd
File: WmsSource.pm

Class: WMTSALAD::WmsSource



Using:
    (start code)
    use WMTSALAD::WmsSource;

    
    (end code)

Attributes:
    
=cut

################################################################################

package WMTSALAD::WmsSource;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK   = ( @{$EXPORT_TAGS{'all'}} );
our @EXPORT      = qw();

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################

BEGIN {}
INIT {}
END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################


=begin nd

Constructor: new

<WMTSALAD::WmsSource's> constructor.

Using:
    (start code)
    new( {
        wms_url     => 
        wms_version => 
        wms_layers  => 
        wms_styles  =>
        wms_format  =>
        wms_crs     =>
        wms_channels =>
    } )
    (end code)

Parameters:
    params - hash reference, containing the following properties :
        {
            
        }

Returns:
    The newly created WmsSource object. 'undef' in case of failure.
    
=cut
sub new() {
    my $this = shift;
    my $params = shift;

    my $class= ref($this) || $this;

    # IMPORTANT : if modification, think to update natural documentation (just above)
    # see config/pyramids/pyramid.xsd to get the list of parameters.
    # TODO : write it
    my $self = {
    };

    bless($self, $class);

    if (!defined $file) {
        return undef;
    }

    if (!$self->_load($params)) {
        ERROR("Could not load pyramid source.");
        return undef;
    }

    return $self;
}

=begin nd

Function: _load

<WMTSALAD::WmsSource's> constructor's annex. Checks parameters passed to 'new', 
then load them in the new WmsSource object.

Using:
    (start code)
    _load( {
        
    } )
    (end code)

Parameters:
    params - hash reference, containing the following properties :
        {
            
        }

Returns:
    TRUE in case of success, FALSE in case of failure.
    
=cut
sub _load() {
    my $self = shift;
    my $params = shift;

    if (!exists $params->{file} || !defined $params->{file}) {
        ERROR("A pyramid descriptor's file file must be passed to load a pryamid source.");
        return FALSE;
    }

    $self->{file} = $params->{file};
    if (exists $params->{style} && defined $params->{style} && $params->{{style}} ne '') {
        $self->{style} = $params->{style};
    }
    if (exists $params->{transparent} && defined $params->{transparent}) {
        if (lc $params->{transparent} eq "true" || $params->{transparent} == TRUE ) {
            $self->{transparent} = "true";
        } elsif (lc $params->{transparent} eq "false" || $params->{transparent} == FALSE ) {
            $self->{transparent} = "false";
        } else {
            WARN(sprintf "Unhandled value for 'transparent' attribute : %s. Ignoring it.", $params->{transparent});
        }
    }

    return TRUE;
}


####################################################################################################
#                                        Group: Output                                             #
####################################################################################################

=begin nd

Function: write

=cut
sub write() {
    return TRUE;
}
