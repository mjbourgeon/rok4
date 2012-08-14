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

package BE4::Process;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use File::Basename;
use File::Path;
use Data::Dumper;

use BE4::Harvesting;
use BE4::Level;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK   = ( @{$EXPORT_TAGS{'all'}} );
our @EXPORT      = qw();

################################################################################
# Constantes
# Booleans
use constant TRUE  => 1;
use constant FALSE => 0;
# Commands
use constant RESULT_TEST => "if [ \$? != 0 ] ; then echo \$0 : Erreur a la ligne \$(( \$LINENO - 1)) >&2 ; exit 1; fi\n";
use constant MERGE_4_TIFF     => "merge4tiff";
# Commands' weights
use constant MERGE4TIFF_W => 1;
use constant MERGENTIFF_W => 4;
use constant CACHE2WORK_PNG_W => 3;
use constant WGET_W => 35;
use constant TIFF2TILE_W => 0;
use constant TIFFCP_W => 0;

################################################################################
# Global

my $BASHFUNCTIONS   = <<'FUNCTIONS';

Wms2work () {
    local dir=$1
    local fmt=$2
    local imgSize=$3
    local nbTiles=$4
    local url=$5
    shift 5

    local size=0

    mkdir $dir

    for i in `seq 1 $#`;
    do
        nameImg=`printf "$dir/img%.2d.$fmt" $i`
        local count=0; local wait_delay=1
        while :
        do
            let count=count+1
            wget --no-verbose -O $nameImg "$url&BBOX=$1"
            if gdalinfo $nameImg 1>/dev/null ; then break ; fi
            
            echo "Failure $count : wait for $wait_delay s"
            sleep $wait_delay
            let wait_delay=wait_delay*2
            if [ 3600 -lt $wait_delay ] ; then 
                let wait_delay=3600
            fi
        done
        let size=`stat -c "%s" $nameImg`+$size

        shift
    done
    
    if [ "$min_size" -ne "0" ]&&[ "$size" -le "$min_size" ] ; then
        rm -rf $nodeName
        return
    fi

    if [ "$fmt" == "png" ]||[ "$nbTiles" != "1x1" ] ; then
        montage -geometry $imgSize -tile $nbTiles $dir/*.$fmt -depth 8 -define tiff:rows-per-strip=4096  $dir.tif
        if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    else
        echo "mv $dir/img01.tif $dir.tif" 
        mv $dir/img01.tif $dir.tif
    fi

    rm -rf $dir
}

Cache2work () {
  local imgSrc=$1
  local workName=$2
  local png=$3

  if [ $png ] ; then
    cp $imgSrc $workName.tif
    mkdir $workName
    untile $workName.tif $workName/
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    montage __montageIn__ $workName/*.png __montageOut__ $workName.tif
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    rm -rf $workName/
  else
    tiffcp __tcp__ $imgSrc $workName.tif
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
  fi

}

Work2cache () {
  local work=$1
  local cache=$2
  
  local dir=`dirname $cache`
  
  if [ -r $cache ] ; then rm -f $cache ; fi
  if [ ! -d  $dir ] ; then mkdir -p $dir ; fi
  
  if [ -f $work ] ; then
    tiff2tile $work __t2t__  $cache
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
  fi
}

MergeNtiff () {
  local type=$1
  local config=$2
  local bg=$3
  mergeNtiff -f $config -t $type __mNt__
  if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
  rm -f $config
  if [ $bg ] ; then
    rm -f $bg
  fi
}

FUNCTIONS

################################################################################

BEGIN {}
INIT {}
END {}

################################################################################
=begin nd
Group: variable

variable: $self
    * pyramid    => undef, # Pyramid object
    * job_number => undef,
    * path_temp  => undef,
    * path_shell => undef,
    
    * scripts => [], # name of each jobs (split and finisher)
    * streams => [], # strems to each jobs (split and finisher)
    * weights => [], # weight of each jobs (split and finisher)

=cut

####################################################################################################
#                                       CONSTRUCTOR METHODS                                        #
####################################################################################################

# Group: constructor

sub new {
    my $this = shift;
    
    my $class= ref($this) || $this;
    # IMPORTANT : if modification, think to update natural documentation (just above) and pod documentation (bottom)
    my $self = {
        # in
        pyramid     => undef,
        #
        job_number  => undef,
        path_temp   => undef,
        path_shell  => undef,
        # out
        scripts => [],
        streams => [],
        weights => [],
    };
    bless($self, $class);

    TRACE;
    
    return undef if (! $self->_init(@_));

    return $self;
}

#
=begin nd
method: _init

Load process' parameters, initialize weights and script (open streams and write headers)

Parameters:
    params_process - job_number, path_temp and path_shell.
    pyr - Pyramid object.
=cut
sub _init {
    my ($self, $params_process, $pyr) = @_;

    TRACE;

    if (! defined $pyr || ref ($pyr) ne "BE4::Pyramid") {
        ERROR("Can not load Pyramid!");
        return FALSE;
    }
    $self->{pyramid} = $pyr;

    $self->{job_number} = $params_process->{job_number}; 
    $self->{path_temp}  = $params_process->{path_temp};
    $self->{path_shell} = $params_process->{path_shell};

    if (! defined $self->{job_number}) {
        ERROR("Parameter required to 'job_number' !");
        return FALSE;
    }

    if (! defined $self->{path_temp}) {
        ERROR("Parameter required to 'path_temp' !");
        return FALSE;
    }

    if (! defined $self->{path_shell}) {
        ERROR("Parameter required to 'path_shell' !");
        return FALSE;
    }
    
    # -------------------------------------------------------------------
    # We create directory for scripts
    if (! -d $self->getScriptDir) {
        DEBUG (sprintf "Create the script directory'%s' !", $self->getScriptDir);
        eval { mkpath([$self->getScriptDir]); };
        if ($@) {
            ERROR(sprintf "Can not create the script directory '%s' : %s !", $self->getScriptDir , $@);
            return FALSE;
        }
    }

    
    # -------------------------------------------------------------------
    # We initialize scripts (name, weights) and open writting streams
    
    my $functions = $self->configureFunctions();
    
    for (my $i = 0; $i <= $self->{job_number}; $i++) {
        my $scriptID = sprintf "SCRIPT_%s",$i;
        $scriptID = "SCRIPT_FINISHER" if ($i == 0);
        push @{$self->{scriptsID}},$scriptID;
        
        my $SCRIPT;
        my $scriptPath = $self->getScriptFile($scriptID);
        if ( ! (open $SCRIPT,">", $scriptPath)) {
            ERROR(sprintf "Can not save the script '%s' !.", $scriptPath);
            return FALSE;
        }
        
        # We write header (environment variables and bash functions)
        my $header = $self->prepareScript($scriptID,$functions);
        printf $SCRIPT "%s", $header;
        # We store stream
        push @{$self->{streams}},$SCRIPT;
        
        # We initialize weight for this script with 0
        push @{$self->{weights}},0;
    }

    return TRUE;
}


####################################################################################################
#                                          WRITER METHODS                                          #
####################################################################################################

# Group: writer methods

#
=begin nd
method: printInScript

Writes commands in the wanted script.

Parameter:
    code - code to write in the current script.
    ind - indice (integer) of the stream in which we want to write code.

=cut
sub printInScript {
    my $self = shift;
    my $code = shift;
    my $ind = shift;

    TRACE;

    my $stream = $self->{streams}[$ind];
    printf ($stream "%s", $code);
}

####################################################################################################
#                                      COMMANDS METHODS                                            #
####################################################################################################

# Group: commands methods

#
=begin nd
method: wms2work

Fetch image corresponding to the node thanks to 'wget', in one or more steps at a time. WMS service is described in the current tree's datasource. Use the 'Wms2work' bash function.

Example:
    Wms2work ${TMP_DIR}/18_8300_5638.tif "http://localhost/wmts/rok4?LAYERS=ORTHO_RAW_LAMB93_D075-E&SERVICE=WMS&VERSION=1.3.0&REQUEST=getMap&FORMAT=image/tiff&CRS=EPSG:3857&BBOX=264166.3697535659936,6244599.462785762557312,266612.354658691633792,6247045.447690888197504&WIDTH=4096&HEIGHT=4096&STYLES="

Parameters:
    node - BE4::Node object, whose image have to be harvested.
    harvesting - BE4::Harvesting object, to use to harvest image.
=cut
sub wms2work {
    my ($self, $node, $harvesting) = @_;
    
    TRACE;
    
    my @imgSize = $self->{pyramid}->getCacheImageSize($node->getLevel); # ie size tile image in pixel !
    my $tms     = $self->{pyramid}->getTileMatrixSet;
    
    my $nodeName = $node->getWorkBaseName;
    my $cmd = $harvesting->getCommandWms2work({
        inversion => $tms->getInversion,
        dir       => "\${TMP_DIR}/".$nodeName,
        srs       => $tms->getSRS,
        bbox      => $node->getBBox,
        imagesize => [$imgSize[0], $imgSize[1]]
    });    
    
    if (! defined $cmd) {
        ERROR("Cannot harvest image for node $nodeName");
        exit 4;
    }
    
    return ($cmd,WGET_W);
}

#
=begin nd
method: cache2work

Copy image from cache to work directory and transform (work format : untiles, uncompressed).
Use the 'Cache2work' bash function.

2 cases:
    - legal tiff compression -> tiffcp
    - png -> untile + montage
    
Examples:
    Cache2work ${PYR_DIR}/IMAGE/19/02/BF/24.tif ${TMP_DIR}/bgImg_19_398_3136 (png)
    
Parameters:
    node - BE4::Node object, whose image have to be transfered in the work directory.
    workName - work file name (level_x_y.tif).
=cut
sub cache2work {
    my ($self, $node, $workName) = @_;

    my @imgSize   = $self->{pyramid}->getCacheImageSize($node->getLevel); # ie size tile image in pixel !
    my $cacheName = $self->{pyramid}->getCacheNameOfImage($node, 'data');
    
    my $dirName = $node->getWorkBaseName;

    if ($self->{pyramid}->getCompression() eq 'png') {
        # Dans le cas du png, l'opération de copie doit se faire en 3 étapes :
        #       - la copie du fichier dans le dossier temporaire
        #       - le détuilage (untile)
        #       - la fusion de tous les png en un tiff
        my $cmd =  sprintf ("Cache2work \${PYR_DIR}/%s \${TMP_DIR}/%s png\n", $cacheName , $dirName);
        return ($cmd,CACHE2WORK_PNG_W);
    } else {
        # Pour le tiffcp on fixe le rowPerStrip au nombre de ligne de l'image ($imgSize[1])
        my $cmd =  sprintf ("Cache2work \${PYR_DIR}/%s \${TMP_DIR}/%s\n", $cacheName ,$dirName);
        return ($cmd,TIFFCP_W);
    }
}

#
=begin nd
method: work2cache

Copy image from work directory to cache and transform it (tiles and compressed) thanks to the 'Work2cache' bash function (tiff2tile).

Example:
    Work2cache ${TMP_DIR}/19_395_3137.tif ${PYR_DIR}/IMAGE/19/02/AF/Z5.tif

Parameter:
    node - node whose image have to be transfered in the cache.
=cut
sub work2cache {
    my $self = shift;
    my $node = shift;
  
    my $tree = $self->{trees}[$self->{currentTree}];
    my $workImgName  = $node->getWorkName;
    my $cacheImgName = $self->{pyramid}->getCacheNameOfImage($node, 'data'); 
    
    my $tm = $self->{pyramid}->getTileMatrixSet()->getTileMatrix($node->{level});
    
    # DEBUG: On pourra mettre ici un appel à convert pour ajouter des infos
    # complémentaire comme le quadrillage des dalles et le numéro du node, 
    # ou celui des tuiles et leur identifiant.
    
    # Suppression du lien pour ne pas corrompre les autres pyramides.
    my $cmd   .= sprintf ("Work2cache \${TMP_DIR}/%s \${PYR_DIR}/%s\n", $workImgName, $cacheImgName);
    
    # Si on est au niveau du haut, il faut supprimer les images, elles ne seront plus utilisées
    
    if ($node->{level} eq $tree->getTopLevelID) {
        $cmd .= sprintf ("rm -f \${TMP_DIR}/%s\n", $workImgName);
    }
    
    return ($cmd,TIFF2TILE_W);
}

#
=begin nd
method: mergeNtiff

Use the 'MergeNtiff' bash function.

Parameters:
    confFile - complete absolute file path to the configuration (list of used images).
    bg - Name of the eventual background (undefined if none).
    dataType - 'data' or 'metadata'.
    
Example:
    MergeNtiff image ${ROOT_TMP_DIR}/mergeNtiff/mergeNtiffConfig_19_397_3134.txt
=cut
sub mergeNtiff {
    my $self = shift;
    my $confFile = shift;
    my $bg = shift; # optionnal
    my $dataType = shift; # param. are image or mtd to mergeNtiff script !

    TRACE;

    $dataType = 'image' if (  defined $dataType && $dataType eq 'data');
    $dataType = 'image' if (! defined $dataType);
    $dataType = 'mtd'   if (  defined $dataType && $dataType eq 'metadata');

    my $cmd = sprintf "MergeNtiff %s %s",$dataType,$confFile;
    
    if (defined $bg) {
        $cmd .= " \${TMP_DIR}/$bg\n";
    } else {
        $cmd .= "\n";
    }

    return ($cmd,MERGENTIFF_W);
}

#
=begin nd
method: merge4tiff

Compose the 'merge4tiff' command.

Parameters:
    resultImg - path to write 'merge4tiff' result.
    backGround - a color or an image.
    childImgParam - images to merge (and their places), from 1 to 4 ("-i1 img1.tif -i3 img2.tif -i4 img3.tif").
|                   i1  i2
| backGround    +              =  resultImg
|                   i3  i4

Example:
    merge4tiff -g 1 -n FFFFFF  -i1 $TMP_DIR/19_396_3134.tif -i2 $TMP_DIR/19_397_3134.tif -i3 $TMP_DIR/19_396_3135.tif -i4 $TMP_DIR/19_397_3135.tif $TMP_DIR/18_198_1567.tif
=cut
sub merge4tiff {
  my $self = shift;
  my $resultImg = shift;
  my $backGround = shift;
  my $childImgParam  = shift;
  
  TRACE;
  
  my $cmd = sprintf "%s -g %s ", MERGE_4_TIFF, $self->{pyramid}->getGamma();
  
  $cmd .= "$backGround ";
  $cmd .= "$childImgParam ";
  $cmd .= sprintf "%s\n%s",$resultImg, RESULT_TEST;
  
  return ($cmd,MERGE4TIFF_W);
}


####################################################################################################
#                                        PUBLIC METHODS                                            #
####################################################################################################

# Group: public methods

#
=begin nd
method: configureFunctions

Configure bash functions to write in scripts' header.
=cut
sub configureFunctions {
    my $self = shift;

    TRACE;

    my $pyr = $self->{pyramid};
    my $configuredFunc = $BASHFUNCTIONS;

    # congigure mergeNtiff
    my $conf_mNt = "";

    my $ip = $pyr->getInterpolation;
    $conf_mNt .= "-i $ip ";
    my $spp = $pyr->getSamplesPerPixel;
    $conf_mNt .= "-s $spp ";
    my $bps = $pyr->getBitsPerSample;
    $conf_mNt .= "-b $bps ";
    my $ph = $pyr->getPhotometric;
    $conf_mNt .= "-p $ph ";
    my $sf = $pyr->getSampleFormat;
    $conf_mNt .= "-a $sf ";

    if ($self->{pyramid}->getNodata->getNoWhite) {
        $conf_mNt .= "-nowhite ";
    }

    my $nd = $self->{pyramid}->getNodata->getValue;
    $conf_mNt .= "-n $nd ";

    $configuredFunc =~ s/__mNt__/$conf_mNt/;

    # configure montage
    my $conf_montageIn = "";

    $conf_montageIn .= sprintf "-geometry %sx%s",$self->{pyramid}->getTileWidth,$self->{pyramid}->getTileHeight;
    $conf_montageIn .= sprintf "-tile %sx%s",$self->{pyramid}->getTilesPerWidth,$self->{pyramid}->getTilesPerHeight;
    
    $configuredFunc =~ s/__montageIn__/$conf_montageIn/;
    
    my $conf_montageOut = "";
    
    $conf_montageOut .= "-depth $bps ";
    
    $conf_montageOut .= sprintf "-define tiff:rows-per-strip=%s ",$self->{pyramid}->getCacheImageHeight;
    if ($spp == 4) {
        $conf_montageOut .= "-background none ";
    }

    $configuredFunc =~ s/__montageOut__/$conf_montageOut/;

    # congigure tiffcp
    my $conf_tcp = "";

    my $imgS = $self->{pyramid}->getCacheImageHeight;
    $conf_tcp .= "-s -r $imgS ";

    $configuredFunc =~ s/__tcp__/$conf_tcp/;

    # congigure tiff2tile
    my $conf_t2t = "";

    my $compression = $pyr->getCompression;
    $conf_t2t .= "-c $compression ";
    if ($pyr->getCompressionOption eq 'crop') {
        $conf_t2t .= "-crop ";
    }

    $conf_t2t .= "-p $ph ";
    $conf_t2t .= sprintf "-t %s %s ",$pyr->getTileMatrixSet->getTileWidth,$pyr->getTileMatrixSet->getTileHeight;
    $conf_t2t .= "-b $bps ";
    $conf_t2t .= "-a $sf ";
    $conf_t2t .= "-s $spp ";

    $configuredFunc =~ s/__t2t__/$conf_t2t/;

    return $configuredFunc;
}

#
=begin nd
method: prepareScript

Compose script's header, which contains environment variables: the script ID, path to work directory, cache... And functions to factorize code.

Parameter:
    scriptId - script whose header have to be add.
    functions - Configured functions, used in the script (mergeNtiff, wget...).

Example:
|   # Variables d'environnement
|   SCRIPT_ID="SCRIPT_1"
|   ROOT_TMP_DIR="/home/TMP/ORTHO"
|   TMP_DIR="/home/ign/TMP/ORTHO"
|   PYR_DIR="/home/ign/PYR/ORTHO"
|
|   # fonctions de factorisation
|   Wms2work () {
|     local img_dst=$1
|     local url=$2
|     local count=0; local wait_delay=60
|     while :
|     do
|       let count=count+1
|       wget --no-verbose -O $img_dst $url 
|       if tiffck $img_dst ; then break ; fi
|       echo "Failure $count : wait for $wait_delay s"
|       sleep $wait_delay
|       let wait_delay=wait_delay*2
|       if [ 3600 -lt $wait_delay ] ; then 
|         let wait_delay=3600
|       fi
|     done
|   }
=cut
sub prepareScript {
    my $self = shift;
    my $scriptId = shift;
    my $functions = shift;

    TRACE;

    # definition des variables d'environnement du script
    my $code = sprintf ("# Variables d'environnement\n");
    $code   .= sprintf ("SCRIPT_ID=\"%s\"\n", $scriptId);
    $code   .= sprintf ("ROOT_TMP_DIR=\"%s\"\n", $self->getRootTmpDir);
    $code   .= sprintf ("TMP_DIR=\"%s\"\n", $self->getScriptTmpDir());
    $code   .= sprintf ("PYR_DIR=\"%s\"\n", $self->{pyramid}->getNewDataDir());
    $code   .= "\n";
    
    # Fonctions
    $code   .= "# Fonctions\n";
    $code   .= "$functions\n";

    # creation du répertoire de travail:
    $code .= "# creation du repertoire de travail\n";
    $code .= "if [ ! -d \"\${TMP_DIR}\" ] ; then mkdir -p \${TMP_DIR} ; fi\n\n";

    return $code;
}

# collectWorkImage
# Récupère les images au format de travail dans les répertoires temporaires des
# scripts de calcul du bas de la pyramide, pour les copier dans le répertoire
# temporaire du script final.
# NOTE
# Pas utilisé pour le moment
#--------------------------------------------------------------------------------------------
sub collectWorkImage {
  my $self = shift;
  my ($node, $scriptId, $finishId) = @_;
  
  TRACE;
  
  my $source = File::Spec->catfile( '${ROOT_TMP_DIR}', $scriptId, $node->getWorkName);
  my $code   = sprintf ("mv %s \$TMP_DIR \n", $source);

  return $code;
}


####################################################################################################
#                                       GETTERS / SETTERS                                          #
####################################################################################################

# Group: getters - setters

sub getRootTmpDir {
  my $self = shift;
  return File::Spec->catdir($self->{path_temp}, $self->{pyramid}->getNewName);
  # ie .../TMP/PYRNAME/
}

sub getScriptTmpDir {
  my $self = shift;
  return File::Spec->catdir($self->{path_temp}, $self->{pyramid}->getNewName);
  #return File::Spec->catdir($self->{path_temp}, $self->{pyramid}->getNewName(), "\${SCRIPT_ID}/");
  # ie .../TMP/PYRNAME/SCRIPT_X/
}

sub getScriptDir {
  my $self = shift;
  
  return File::Spec->catdir($self->{path_shell});
}

sub getScriptFile {
  my $self = shift;
  my $scriptID = shift;
  
  return File::Spec->catdir($self->{path_shell}, $scriptID.".sh");
}

sub getJobNumber {
  my $self = shift;
  return $self->{job_number}; 
}

sub getNodata {
  my $self = shift;
  return $self->{nodata}; 
}

sub getWeights {
  my $self = shift;
  return $self->{weights}; 
}

1;
__END__

# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

BE4::Process - compose scripts to generate the cache

=head1 SYNOPSIS

    use BE4::Process;
  
    # Process object creation
    my $objProcess = BE4::Process->new(
        $params->{process},
        $objPyramid
    );

    # Scripts generation
    if (! $objProcess->computeTrees()) {
        ERROR ("Can not compute process !");
        return FALSE;
    }

=head1 DESCRIPTION

=over 4

=item pyramid

A Pyramid object.

=item nodata

A NoData object.

=item trees

An array of Tree objects, one per data source.

=item scripts

Array of string, names of each jobs (split and finisher)

=item codes

Array of string, codes of each jobs (split and finisher)

=item weights

Array of integer, weights of each jobs (split and finisher)

=item currentTree

Integer, indice of the tree in process.

=item job_number

Number of split scripts. If job_number = 5 -> 5 split scripts (can run in parallel) + one finisher (when splits are finished) = 6 scripts. Splits generate cache from bottom level to cut level, and the finisher from the cut level to the top level.

=item path_temp

Temporary directory path in which we create a directory named like the new cache : temporary files are written in F<path_temp/pyr_name_new>. This directory is used to store raw images (uncompressed and untiled). They are removed as and when we don't need them any more. We write in mergeNtiff configurations too.

=item path_shell

Directory path, to write scripts in. Scripts are named F<SCRIPT_1.sh>,F<SCRIPT_2.sh>... and F<SCRIPT_FINISHER.sh> for all generation. That's why the path_shell must be specific to the generation (contains the name of the pyramid for example).

=back

=head1 SEE ALSO

=head2 POD documentation

=begin html

<ul>
<li><A HREF="./lib-BE4-Tree.html">BE4::Tree</A></li>
<li><A HREF="./lib-BE4-NoData.html">BE4::NoData</A></li>
<li><A HREF="./lib-BE4-Pyramid.html">BE4::Pyramid</A></li>
<li><A HREF="./lib-BE4-Harvesting.html">BE4::Harvesting</A></li>
</ul>

=end html

=head2 NaturalDocs

=begin html

<A HREF="../Natural/Html/index.html">Index</A>

=end html

=head1 AUTHOR

Satabin Théo, E<lt>theo.satabin@ign.frE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Satabin Théo

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself, either Perl version 5.10.1 or, at your option, any later version of Perl 5 you may have available.

=cut
