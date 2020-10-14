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
File: ProxyStorage.pm

Class: COMMON::ProxyStorage

(see ROK4GENERATION/libperlauto/COMMON_ProxyStorage.png)

Proxy to manipulate different storage types : object or file, we can copy, reference or remove from one to another

Using:
    (start code)
    use COMMON::ProxyStorage;
    (end code)
=cut

################################################################################

package COMMON::ProxyStorage;

use strict;
use warnings;

use Data::Dumper;
use Digest::SHA;
use File::Map qw(map_file);
use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Response;
use LWP::UserAgent;
use File::Basename;
use JSON;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK   = ( @{$EXPORT_TAGS{'all'}} );
our @EXPORT      = qw();

use Log::Log4perl qw(:easy);

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

my @STORAGETYPES = ("FILE", "CEPH", "S3", "SWIFT");

my $UA;

### CEPH

my $ROK4_CEPH_CONFFILE;
my $ROK4_CEPH_USERNAME;
my $ROK4_CEPH_CLUSTERNAME;

### S3

my $ROK4_S3_URL;
my $ROK4_S3_KEY;
my $ROK4_S3_SECRETKEY;

my $ROK4_S3_ENDPOINT_HOST;

### SWIFT
# global
my $ROK4_SWIFT_AUTHURL;
my $ROK4_SWIFT_USER;
my $ROK4_SWIFT_PASSWD;

my $SWIFT_TOKEN;
my $ROK4_SWIFT_PUBLICURL;
my $ROK4_KEYSTONE_IS_USED;

# swift authentication
my $ROK4_SWIFT_ACCOUNT;

# keystone authentication
my $ROK4_KEYSTONE_DOMAINID;
my $ROK4_KEYSTONE_PROJECTID;

### General
my $ROK4_IMAGE_HEADER_SIZE = 2048;
# Signature d'un objet CEPH LIEN et sa taille
use constant ROK4_SYMLINK_SIGNATURE_SIZE => 8;
use constant ROK4_SYMLINK_SIGNATURE => "SYMLINK#";

####################################################################################################
#                             Group: Controls methods                                              #
####################################################################################################

=begin nd
Function: checkEnvironmentVariables

Return TRUE if all required environment variables for storage are defined FALSE otherwise
=cut
sub checkEnvironmentVariables {
    my $type = shift;
    my $keystone = shift;

    if ($type eq "CEPH") {

        if (! defined $ENV{ROK4_CEPH_CONFFILE}) {
            ERROR("Environment variable ROK4_CEPH_CONFFILE is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_CEPH_USERNAME}) {
            ERROR("Environment variable ROK4_CEPH_USERNAME is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_CEPH_CLUSTERNAME}) {
            ERROR("Environment variable ROK4_CEPH_CLUSTERNAME is not defined");
            return FALSE;
        }

        $ROK4_CEPH_CONFFILE = $ENV{ROK4_CEPH_CONFFILE};
        $ROK4_CEPH_USERNAME = $ENV{ROK4_CEPH_USERNAME};
        $ROK4_CEPH_CLUSTERNAME = $ENV{ROK4_CEPH_CLUSTERNAME};

        
    } elsif ($type eq "SWIFT") {

        if (! defined $ENV{ROK4_SWIFT_AUTHURL}) {
            ERROR("Environment variable ROK4_SWIFT_AUTHURL is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_SWIFT_USER}) {
            ERROR("Environment variable ROK4_SWIFT_USER is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_SWIFT_PASSWD}) {
            ERROR("Environment variable ROK4_SWIFT_PASSWD is not defined");
            return FALSE;
        }

        $ROK4_SWIFT_PASSWD = $ENV{ROK4_SWIFT_PASSWD};
        $ROK4_SWIFT_USER = $ENV{ROK4_SWIFT_USER};
        $ROK4_SWIFT_AUTHURL = $ENV{ROK4_SWIFT_AUTHURL};

        if ($keystone) {
            if (! defined $ENV{ROK4_KEYSTONE_DOMAINID}) {
                ERROR("Environment variable ROK4_KEYSTONE_DOMAINID is not defined");
                ERROR("We need it for a keystone authentication (swift)");
                return FALSE;
            }

            if (! defined $ENV{ROK4_SWIFT_PUBLICURL}) {
                ERROR("Environment variable ROK4_SWIFT_PUBLICURL is not defined");
                ERROR("We need it for a keystone authentication (swift)");
                return FALSE;
            }

            if (! defined $ENV{ROK4_KEYSTONE_PROJECTID}) {
                ERROR("Environment variable ROK4_KEYSTONE_PROJECTID is not defined");
                ERROR("We need it for a keystone authentication (swift)");
                return FALSE;
            }

            $ROK4_KEYSTONE_DOMAINID = $ENV{ROK4_KEYSTONE_DOMAINID};
            $ROK4_KEYSTONE_PROJECTID = $ENV{ROK4_KEYSTONE_PROJECTID};
            $ROK4_SWIFT_PUBLICURL = $ENV{ROK4_SWIFT_PUBLICURL};
            $ROK4_KEYSTONE_IS_USED = TRUE;
        } else {
            
            if (! defined $ENV{ROK4_SWIFT_ACCOUNT}) {
                ERROR("Environment variable ROK4_SWIFT_ACCOUNT is not defined");
                ERROR("We need it for a swift authentication");
                return FALSE;
            }
            $ROK4_KEYSTONE_IS_USED = FALSE;
            $ROK4_SWIFT_ACCOUNT = $ENV{ROK4_SWIFT_ACCOUNT};
        }

        $UA = LWP::UserAgent->new();
        $UA->ssl_opts(verify_hostname => 0);
        $UA->env_proxy;

    } elsif ($type eq "S3") {
        
        if (! defined $ENV{ROK4_S3_URL}) {
            ERROR("Environment variable ROK4_S3_URL is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_S3_KEY}) {
            ERROR("Environment variable ROK4_S3_KEY is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_S3_SECRETKEY}) {
            ERROR("Environment variable ROK4_S3_SECRETKEY is not defined");
            return FALSE;
        }

        $ROK4_S3_URL = $ENV{ROK4_S3_URL};
        $ROK4_S3_KEY = $ENV{ROK4_S3_KEY};
        $ROK4_S3_SECRETKEY = $ENV{ROK4_S3_SECRETKEY};

        $ROK4_S3_ENDPOINT_HOST = $ROK4_S3_URL;
        $ROK4_S3_ENDPOINT_HOST =~ s/^https?:\/\///;
        $ROK4_S3_ENDPOINT_HOST =~ s/:[0-9]+$//;

        $UA = LWP::UserAgent->new();
        $UA->ssl_opts(verify_hostname => 0);
        $UA->env_proxy;
    }

    return TRUE;
}


####################################################################################################
#                            Group: Connection methods                                             #
####################################################################################################

=begin nd
Function: getSwiftToken

Return TRUE if swift token (with keystone or not) is valid FALSE otherwise
=cut
sub getSwiftToken {

    if (! defined($ROK4_SWIFT_USER) || ! defined($ROK4_SWIFT_PASSWD)) {
        ERROR("Cannot get Swift token without user credentials. Please make sure the environment variables were loaded.");
        return FALSE;
    }
    if ($ROK4_KEYSTONE_IS_USED) {

        my $body_object = {
            "auth" => {
                "scope" => {
                    "project" => {
                        "id" => "$ROK4_KEYSTONE_PROJECTID"
                    }
                },
                "identity" => {
                    "methods" => [
                        "password"
                    ],
                    "password" => {
                        "user" => {
                            "domain" => {
                                "id" => "$ROK4_KEYSTONE_DOMAINID"
                            },
                            "name" => "$ROK4_SWIFT_USER",
                            "password" => "$ROK4_SWIFT_PASSWD"
                        }
                    }
                }
            }
        };
        my $json = JSON::to_json($body_object, {utf8 => 1});

        my $request = HTTP::Request::Common::POST(
            $ROK4_SWIFT_AUTHURL,
            Content_Type => "application/json",
            Content => $json
        );

        my $response = $UA->request($request);

        if (! defined $response || ! $response->is_success() ) {
            ERROR("Cannot get Swift token via Keystone");
            ERROR(Dumper($response));
            return FALSE;
        }

        $SWIFT_TOKEN = $response->header("X-Subject-Token");
        
        if (! defined $SWIFT_TOKEN) {
            ERROR("No token in the keystone authentication response");
            ERROR(Dumper($response));
            return FALSE;
        }
    } else {

        my $request = HTTP::Request::Common::GET(
            $ROK4_SWIFT_AUTHURL
        );

        $request->header('X-Storage-User' => "$ROK4_SWIFT_ACCOUNT:$ROK4_SWIFT_USER");
        $request->header('X-Storage-Pass' => "$ROK4_SWIFT_PASSWD");
        $request->header('X-Auth-User' => "$ROK4_SWIFT_ACCOUNT:$ROK4_SWIFT_USER");
        $request->header('X-Auth-Key' => "$ROK4_SWIFT_PASSWD");

        my $response = $UA->request($request);

        if (! defined $response || ! $response->is_success() ) {
            ERROR("Cannot get Swift token");
            return FALSE;
        }

        $SWIFT_TOKEN = $response->header("X-Auth-Token");
        $ROK4_SWIFT_PUBLICURL = $response->header("X-Storage-Url");
        
        if (! defined $SWIFT_TOKEN) {
            ERROR("No token in the swift authentication response");
            ERROR(Dumper($response));
            return FALSE;
        }
        if (! defined $ROK4_SWIFT_PUBLICURL) {
            ERROR("No public URL in the swift authentication response");
            ERROR(Dumper($response));
            return FALSE;
        }
    }

    return TRUE;
}

=begin nd
Function: sendSwiftRequest

Parameters:
    $request - HTTP::Request - the request to send to SWIFT
    $parm1, $parm2, ... - optionnal - Any additionnal parameters for LWP::UserAgent->request()

Send the request to swift once then, in case of failure, refresh the authorization token, then retry.

Returns:
    HTTP::Response - the last request's response.
=cut
sub sendSwiftRequest {
    my @parameters = shift;
    # $parameters[0] is the HTTP::Request object
    $parameters[0]->header('X-Auth-Token' => $SWIFT_TOKEN);

    my $response = $UA->request(@parameters);
    if (defined($response) && $response->is_success) {
        return $response;
    }

    WARNING("Swift request failed once. Refreshing SWIFT token.");
    if (! getSwiftToken()) {
        ERROR("Cannot refresh swift token");
        return $response;
    }

    INFO("Retrying...");
    $parameters[0]->header('X-Auth-Token' => $SWIFT_TOKEN);
    $response = $UA->request(@parameters);
    return $response;
}

####################################################################################################
#                               Group: Copy methods                                                #
####################################################################################################

=begin nd
Function: copy

Return TRUE if success FALSE otherwise
=cut
sub copy {
    my $fromType = shift;
    my $fromPath = shift;
    my $toType = shift;
    my $toPath = shift;

    DEBUG("Copying from '$fromType' path '$fromPath', to '$toType' path '$toPath'.");
    if ($fromType eq 'SWIFT' || $toType eq 'SWIFT') {
        if($ROK4_KEYSTONE_IS_USED) {
            DEBUG("Using keystone authentication.");
        }
        else {
            DEBUG("Using SWIFT native authentication.");
        }
    }

    if ($fromType eq "FILE") { ############################################ FILE
        if ($toType eq "FILE") {

            # create folder
            my $dir = File::Basename::dirname($toPath);
            `mkdir -p $dir`;
            if ($?) {
                ERROR("Cannot create directory '$dir' : $!");
                return FALSE;
            }
        
            `cp $fromPath $toPath`;
            if ($?) {
                ERROR("Cannot copy from file '$fromPath' to file '$toPath' : $!");
                return FALSE;
            }
            return TRUE;
        }
        elsif ($toType eq "CEPH") {
            my ($poolName, @rest) = split("/", $toPath);
            my $objectName = join("", @rest);

            if (! defined $poolName || ! defined $objectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $toPath");
                return FALSE;
            }

            `rados -p $poolName put $objectName $fromPath`;
            if ($?) {
                ERROR("Cannot upload file '$fromPath' to CEPH object $objectName (pool $poolName): $!");
                return FALSE;
            }

            return TRUE;
        }
        elsif ($toType eq "S3") {
            my ($bucketName, @rest) = split("/", $toPath);
            my $objectName = join("", @rest);

            if (! defined $bucketName || ! defined $objectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $toPath");
                return FALSE;
            }

            my $body;

            map_file $body, $fromPath;

            my $resource = "/$bucketName/$objectName";
            my $contentType="application/octet-stream";
            my $dateValue=`TZ=GMT date -R`;
            chomp($dateValue);
            my $stringToSign="PUT\n\n$contentType\n$dateValue\n$resource";

            my $signature = Digest::SHA::hmac_sha1_base64($stringToSign, $ROK4_S3_SECRETKEY);
            while (length($signature) % 4) {
                $signature .= '=';
            }

            # set custom HTTP request header fields
            my $request = HTTP::Request->new(PUT => $ROK4_S3_URL.$resource);
            $request->content($body);
            $request->header('Host' => $ROK4_S3_ENDPOINT_HOST);
            $request->header('Date' => $dateValue);
            $request->header('Content-Type' => $contentType);
            $request->header('Authorization' => sprintf ("AWS %s:$signature", $ROK4_S3_KEY));
             
            my $response = $UA->request($request);
            if ($response->is_success) {
                return TRUE;
            }
            else {
                ERROR("Cannot upload file '$fromPath' to S3 object $objectName (bucket $bucketName)");
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
        elsif ($toType eq "SWIFT") {
            if (! defined ($SWIFT_TOKEN) ) {
                if (! getSwiftToken()) {
                    ERROR("Cannot get swift token");
                    return FALSE;
                }
            }
            my ($containerName, @rest) = split("/", $toPath);
            my $objectName = join("", @rest);

            if (! defined $containerName || ! defined $objectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my $context = "/$containerName/$objectName";

            my $body;

            map_file $body, $fromPath;

            
            my $request = HTTP::Request->new(PUT => $ROK4_SWIFT_PUBLICURL.$context);

            $request->content($body);
            my $response = sendSwiftRequest($request);
            if ($response->is_success) {
                return TRUE;
            } 
            else {
                ERROR("Cannot upload SWIFT object '$toPath' from file $fromPath");
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
            
        }
    }
    elsif ($fromType eq "CEPH") { ############################################ CEPH
        if ($toType eq "FILE") {

            # On regarde si c'est un objet symbolique, pour copier le vrai objet
            my $realFromPath = getRealData("CEPH", $fromPath);
            if ( ! defined $realFromPath ) {
                ERROR("Objet to download '$fromPath' does not exists");
                return undef;
            }

            my ($poolName, @rest) = split("/", $realFromPath);
            my $objectName = join("", @rest);

            if (! defined $poolName || ! defined $objectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $fromPath");
                return FALSE;
            }

            # create folder
            my $dir = File::Basename::dirname($toPath);
            `mkdir -p $dir`;
            if ($?) {
                ERROR("Cannot create directory '$dir' : $!");
                return FALSE;
            }

            `rados -p $poolName get $objectName $toPath`;
            if ($@) {
                ERROR("Cannot download CEPH object $fromPath into file '$toPath': $@");
                if ($realFromPath ne $fromPath) {
                    ERROR("'$fromPath' is a symbolic objet which references '$realFromPath' which does not exist (broken link ?)")
                }
                return FALSE;
            }

            return TRUE;
        }
        elsif ($toType eq "CEPH") {

            # On regarde si c'est un objet symbolique, pour copier le vrai objet
            my $realFromPath = getRealData("CEPH", $fromPath);
            if ( ! defined $realFromPath ) {
                ERROR("Objet to copy '$fromPath' does not exists");
                return undef;
            }

            my ($fromPool, @from) = split("/", $fromPath);
            my $fromObjectName = join("", @from);

            if (! defined $fromPool || ! defined $fromObjectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my ($toPool, @to) = split("/", $toPath);
            my $toObjectName = join("", @to);

            if (! defined $toPool || ! defined $toObjectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $toPath");
                return FALSE;
            }

            if ($toPool ne $fromPool) {
                ERROR("CEPH copy is not possible for different pool: $fromPath -> X $toPath");
                return FALSE;
            }

            `rados -p $toPool cp $fromObjectName $toObjectName`;
            if ($?) {
                ERROR("Cannot copy CEPH object $fromObjectName -> $toObjectName (pool $fromPool): $!");
                return FALSE;
            }

            return TRUE;
        }
        elsif ($toType eq "SWIFT") {
            ERROR("CEPH to SWIFT copy is not implemented.");            
            return FALSE;
        }
    }
    elsif ($fromType eq "S3") { ############################################ S3
        if ($toType eq "FILE") {

            my ($bucketName, @rest) = split("/", $fromPath);
            my $objectName = join("", @rest);

            if (! defined $bucketName || ! defined $objectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my $context = "/$bucketName/$objectName";
            my $content_type = "application/octet-stream";
            my $date_gmt = `TZ=GMT date -R`;
            chomp($date_gmt);
            my $string_to_sign="GET\n\n$content_type\n$date_gmt\n$context";

            my $signature = Digest::SHA::hmac_sha1_base64($string_to_sign, $ROK4_S3_SECRETKEY);
            while (length($signature) % 4) {
                $signature .= '=';
            }

            my $request = HTTP::Request->new(GET => $ROK4_S3_URL.$context);

            $request->header('Host' => $ROK4_S3_ENDPOINT_HOST);
            $request->header('Date' => $date_gmt);
            $request->header('Content-Type' => $content_type);
            $request->header('Authorization' => sprintf ("AWS %s:$signature", $ROK4_S3_KEY));
             
            # create folder
            my $dir = File::Basename::dirname($toPath);
            `mkdir -p $dir`;
            if ($?) {
                ERROR("Cannot create directory '$dir' : $!");
                return FALSE;
            }

            my $response = $UA->request($request, $toPath);
            if ($response->is_success) {
                return TRUE;
            } else {
                ERROR("Cannot download S3 object '$fromPath' to file $toPath");
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
        elsif ($toType eq "S3") {

            my ($fromBucket, @from) = split("/", $fromPath);
            my $fromObjectName = join("", @from);

            if (! defined $fromBucket || ! defined $fromObjectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my ($toBucket, @to) = split("/", $toPath);
            my $toObjectName = join("", @to);

            if (! defined $toBucket || ! defined $toObjectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $toPath");
                return FALSE;
            }

            my $context = "/$toBucket/$toObjectName";
            my $content_type = "application/octet-stream";
            my $date_gmt = `TZ=GMT date -R`;
            chomp($date_gmt);
            my $string_to_sign="PUT\n\n$content_type\n$date_gmt\n$context";

            my $signature = Digest::SHA::hmac_sha1_base64($string_to_sign, $ROK4_S3_SECRETKEY);
            while (length($signature) % 4) {
                $signature .= '=';
            }

            my $request = HTTP::Request->new(PUT => $ROK4_S3_URL.$context);

            $request->header('Host' => $ROK4_S3_ENDPOINT_HOST);
            $request->header('Date' => $date_gmt);
            $request->header('Content-Type' => $content_type);
            $request->header('x-amz-copy-source' => "/$fromBucket/$fromObjectName");
            $request->header('Authorization' => sprintf ("AWS %s:$signature", $ROK4_S3_KEY));

            my $response = $UA->request($request, $toPath);
            if ($response->is_success) {
                return TRUE;
            } else {
                ERROR("Cannot copy S3 object '$fromPath' to S3 object '$toPath'");
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
    }
    elsif ($fromType eq "SWIFT") { ############################################ SWIFT
        if (! defined ($SWIFT_TOKEN) ) {
            if (! getSwiftToken()) {
                ERROR("Cannot get swift token");
                return FALSE;
            }
        }
        if ($toType eq "FILE") {

            my ($containerName, @rest) = split("/", $fromPath);
            my $objectName = join("", @rest);

            if (! defined $containerName || ! defined $objectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my $context = "/$containerName/$objectName";

            my $request = HTTP::Request->new(GET => $ROK4_SWIFT_PUBLICURL.$context);

            
            # create folder
            my $dir = File::Basename::dirname($toPath);
            `mkdir -p $dir`;
            if ($?) {
                ERROR("Cannot create directory '$dir' : $!");
                return FALSE;
            }


            my $response = sendSwiftRequest($request, $toPath);
            if ($response->is_success) {
                return TRUE;
            } else {
                ERROR("Cannot download SWIFT object '$fromPath' to file $toPath");
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
        elsif ($toType eq "SWIFT") {

            my ($fromContainer, @from) = split("/", $fromPath);
            my $fromObjectName = join("", @from);

            if (! defined $fromContainer || ! defined $fromObjectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my ($toContainer, @to) = split("/", $toPath);
            my $toObjectName = join("", @to);

            if (! defined $toContainer || ! defined $toObjectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $toPath");
                return FALSE;
            }

            my $context = "/$fromContainer/$fromObjectName";

            for (my $try_count = 0; $try_count < 2; $try_count++) {
                my $request = HTTP::Request->new(COPY => $ROK4_SWIFT_PUBLICURL.$context);

                $request->header('Destination' => "$toContainer/$toObjectName");

                my $response = sendSwiftRequest($request);
                if ($response->is_success) {
                    return TRUE;
                } 
                elsif ($try_count == 0) {
                    WARNING("Refreshing SWIFT token.");
                    if (! getSwiftToken()) {
                        ERROR("Cannot get swift token");
                        return FALSE;
                    }
                    next;
                }
                else {
                    ERROR("Cannot copy SWIFT object : '$fromPath' -> '$toPath'");
                    ERROR("HTTP code: ", $response->code);
                    ERROR("HTTP message: ", $response->message);
                    ERROR("HTTP decoded content : ", $response->decoded_content);
                    return FALSE;
                }

            }
            
        }
    }

    return FALSE;
}


####################################################################################################
#                               Group: Test methods                                                #
####################################################################################################

=begin nd
Function: whatIs

Return string DIRECTORY, LINK, or REAL
=cut
sub whatIs {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {
        if (-d $path) {
            return "DIRECTORY";
        }
        if (-l $path) {
            return "LINK";
        }
        if (-f $path) {
            return "REAL";
        }
    }
    elsif ($type eq "CEPH") {
        return undef;
    }
    elsif ($type eq "S3") {
        return undef;
    }

    return undef;
}

=begin nd
Function: isPresent

Return TRUE or FALSE
=cut
sub isPresent {
    my $type = shift;
    my $path = shift;

    DEBUG("$type $path isPresent ?");

    if ($type eq "FILE") {
        if (-f $path) {
            return TRUE;
        }
        if (-d $path) {
            return TRUE;
        }

        return FALSE;
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return FALSE;
        }

        `rados -p $poolName stat $objectName 1>/dev/null 2>/dev/null`;
        if ($?) {
            return FALSE;
        }

        return TRUE;
    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return FALSE;
        }

        my $resource = "/$bucketName/$objectName";
        my $contentType="application/octet-stream";
        my $dateValue=`TZ=GMT date -R`;
        chomp($dateValue);
        my $stringToSign="HEAD\n\n$contentType\n$dateValue\n$resource";

        my $signature = Digest::SHA::hmac_sha1_base64($stringToSign, $ROK4_S3_SECRETKEY);
        while (length($signature) % 4) {
            $signature .= '=';
        }

        # set custom HTTP request header fields
        my $request = HTTP::Request->new(HEAD => $ROK4_S3_URL.$resource);
        $request->header('Host' => $ROK4_S3_ENDPOINT_HOST);
        $request->header('Date' => $dateValue);
        $request->header('Content-Type' => $contentType);
        $request->header('Authorization' => sprintf ("AWS %s:$signature", $ROK4_S3_KEY));
         
        my $response = $UA->request($request);
        if ($response->is_success) {
            return TRUE;
        } else {
            return FALSE;
        }
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $containerName || ! defined $objectName) {
            ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $path");
            return FALSE;
        }

        my $context = "/$containerName/$objectName";

        my $request = HTTP::Request->new(HEAD => $ROK4_SWIFT_PUBLICURL.$context);

        $request->header('X-Auth-Token' => $SWIFT_TOKEN);

        my $response = $UA->request($request);
        if ($response->is_success) {
            return TRUE;
        } else {
            return FALSE;
        }
    }

    return FALSE;
}


=begin nd
Function: getRealData

Return the target if file/object is a symbolic file/object, and return the provided file/object if real. Return undef if file/object does not exist.
=cut
sub getRealData {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {

        if (! -e $path) {
            return undef;
        }
        elsif (-f $path && ! -l $path) {
            return $path;
        }
        elsif (-f $path && -l $path) {
            my $realTarget = File::Spec::Link->full_resolve( File::Spec::Link->linked($path) );
            return $realTarget;
        }
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return undef;
        }

        my $value = getSize("CEPH",$path);

        if ( ! defined $value ) {
            return undef;
        }

        if ( $value < $ROK4_IMAGE_HEADER_SIZE ) {

            my $realTarget = `rados -p $poolName get $objectName /dev/stdout`;
            chomp $realTarget;

            # Dans le cas d'un objet Ceph lien, on vérifie que la signature existe bien dans le header
            if (index($realTarget, ROK4_SYMLINK_SIGNATURE) == -1) {
                ERROR("CEPH object is not a valid SYMLINK object : $path");
                return undef;
            }

            $realTarget = substr $realTarget, ROK4_SYMLINK_SIGNATURE_SIZE;
            return "$poolName/$realTarget";

        } else {
            return $path;
        }
    }
    elsif ($type eq "S3") {
        return $path;
    }
    elsif ($type eq "SWIFT") {
        return $path;
    }

    return undef;
}

####################################################################################################
#                               Group: Content methods                                             #
####################################################################################################

=begin nd
Function: getSize

Return size of file/object
=cut
sub getSize {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {
        return -s $path;
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $containerName || ! defined $objectName) {
            ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $path");
            return FALSE;
        }

        my $context = "/$containerName/$objectName";

        my $request = HTTP::Request->new(HEAD => $ROK4_SWIFT_PUBLICURL.$context);

        $request->header('X-Auth-Token' => $SWIFT_TOKEN);

        my $response = $UA->request($request);
        if ($response->is_success) {
            return $response->header("Content-Length");
        }
        else {
            ERROR("HTTP code: ", $response->code);
            ERROR("HTTP message: ", $response->message);
            ERROR("HTTP decoded content : ", $response->decoded_content);
            return undef;
        }
    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return FALSE;
        }

        my $resource = "/$bucketName/$objectName";
        my $contentType="application/octet-stream";
        my $dateValue=`TZ=GMT date -R`;
        chomp($dateValue);
        my $stringToSign="HEAD\n\n$contentType\n$dateValue\n$resource";

        my $signature = Digest::SHA::hmac_sha1_base64($stringToSign, $ROK4_S3_SECRETKEY);
        while (length($signature) % 4) {
            $signature .= '=';
        }

        # set custom HTTP request header fields
        my $request = HTTP::Request->new(HEAD => $ROK4_S3_URL.$resource);
        $request->header('Host' => $ROK4_S3_ENDPOINT_HOST);
        $request->header('Date' => $dateValue);
        $request->header('Content-Type' => $contentType);
        $request->header('Authorization' => sprintf ("AWS %s:$signature", $ROK4_S3_KEY));
         
        my $response = $UA->request($request);
        if ($response->is_success) {
            return $response->header("Content-Length");
        }
        else {
            ERROR("HTTP code: ", $response->code);
            ERROR("HTTP message: ", $response->message);
            ERROR("HTTP decoded content : ", $response->decoded_content);
            return undef;
        }
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return undef;
        }

        my $ret = `rados -p $poolName stat $objectName`;
        if ($@) {
            ERROR("Cannot stat CEPH object $objectName (pool $poolName): $!");
            return undef;
        }

        return (split(/ /, $ret))[-1];
    }

    return undef;
}

####################################################################################################
#                               Group: Delete methods                                              #
####################################################################################################

=begin nd
Function: remove

Remove the file/object provided
=cut
sub remove {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {
        `rm -r $path`;
        if ($? == 0) {return TRUE;}
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("", @rest);

        `rados -p $poolName rm $objectName`;
        if (! $@) {return TRUE;}
    }

    return FALSE;
}

####################################################################################################
#                               Group: Link methods                                                #
####################################################################################################

=begin nd
Function: symLink

Return the real file/object linked if success, undef otherwise
=cut
sub symLink {
    my $targetType = shift;
    my $targetPath = shift;
    my $toType = shift;
    my $toPath = shift;

    if ($targetType eq "FILE" && $toType eq "FILE") {
        # create folder
        my $dir = File::Basename::dirname($toPath);
        `mkdir -p $dir`;
        if ($?) {
            ERROR("Cannot create directory '$dir' : $!");
            return undef;
        }

        my $realTargetPath = getRealData("FILE", $targetPath);
        if ( ! defined $realTargetPath ) {
            ERROR(sprintf "The file '%s' (to symlink) is not a file or a link in '%s' !", basename($targetPath), dirname($targetPath));
            return undef;
        }

        my $relativeTargetPath = File::Spec->abs2rel($realTargetPath,$dir);

        my $result = eval { symlink ($relativeTargetPath, $toPath); };
        if (! $result) {
            ERROR (sprintf "The file '%s' can not be linked by '%s' (%s) ?", $targetPath, $toPath, $!);
            return undef;
        }

        return $realTargetPath;
    }
    elsif ($targetType eq "CEPH" && $toType eq "CEPH") {

        # On vérifie que la dalle CEPH à lier n'est pas un alias, auquel cas on référence le vrai objet (pour éviter des alias en cascade)
        my $realTarget = getRealData("CEPH", $targetPath);
        if ( ! defined $realTarget ) {
            ERROR("Objet to link '$targetPath' does not exists");
            return undef;
        }

        my ($tPoolName, @rest) = split("/", $realTarget);
        $realTarget = join("", @rest);

        (my $toPoolName, @rest) = split("/", $toPath);
        $toPath = join("", @rest);

        if ($tPoolName ne $toPoolName) {
            ERROR("CEPH link (symbolic object) is not possible between different pool: $toPoolName/toPath -> X $targetPath");
            return undef;
        }

        my $symlink_content = ROK4_SYMLINK_SIGNATURE . $realTarget;
        eval { `echo -n "$symlink_content" | rados -p $toPoolName put $toPath /dev/stdin` };

        if ($@) {
            ERROR("Cannot symlink (make a rados put) object $realTarget with alias $toPath : $@");
            return undef;
        }

        return "$tPoolName/$realTarget";
    }
    elsif ($targetType eq "S3" && $toType eq "S3") {
        ERROR("Cannot symlink for S3 storage");
        return undef;
    }
    elsif ($targetType eq "SWIFT" && $toType eq "SWIFT") {
        ERROR("Cannot symlink for SWIFT storage");
        return undef;
    }

    ERROR("Symlink can only be done between two file/path using the same storage type (and not $toType -> $targetType)");
    return undef;
}

=begin nd
Function: hardLink

Return TRUE if success FALSE otherwise
=cut
sub hardLink {
    my $targetType = shift;
    my $targetPath = shift;
    my $toType = shift;
    my $toPath = shift;

    if ($targetType eq "FILE" && $toType eq "FILE") {

        # create folder
        my $dir = File::Basename::dirname($toPath);
        `mkdir -p $dir`;
        if ($?) {
            ERROR("Cannot create directory '$dir' : $!");
            return FALSE;
        }

        my $realTarget;
        if (-f $targetPath && ! -l $targetPath) {
            $realTarget = $targetPath;
        }
        elsif (-f $targetPath && -l $targetPath) {
            $realTarget = File::Spec::Link->full_resolve( File::Spec::Link->linked($targetPath) );
        } else {
            ERROR(sprintf "The file (to hardlink) '%s' is not a file or a link in '%s' !", basename($targetPath), dirname($targetPath));
            return FALSE;
        }

        `ln $targetPath $toPath`;
        if ($?) {
            ERROR("Cannot link (hard) file $targetPath from file $toPath : $!");
            return FALSE;
        }

        return TRUE;
    }

    ERROR("Symlink can only be done between two files (and not $toType -> $targetType)");
    return FALSE;
}

1;
__END__
