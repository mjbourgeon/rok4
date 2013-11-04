/*
 * Copyright © (2011) Institut national de l'information
 *                    géographique et forestière
 *
 * Géoportail SAV <geop_services@geoportail.fr>
 *
 * This software is a computer program whose purpose is to publish geographic
 * data using OGC WMS and WMTS protocol.
 *
 * This software is governed by the CeCILL-C license under French law and
 * abiding by the rules of distribution of free software.  You can  use,
 * modify and/ or redistribute the software under the terms of the CeCILL-C
 * license as circulated by CEA, CNRS and INRIA at the following URL
 * "http://www.cecill.info".
 *
 * As a counterpart to the access to the source code and  rights to copy,
 * modify and redistribute granted by the license, users are provided only
 * with a limited warranty  and the software's author,  the holder of the
 * economic rights,  and the successive licensors  have only  limited
 * liability.
 *
 * In this respect, the user's attention is drawn to the risks associated
 * with loading,  using,  modifying and/or developing or reproducing the
 * software by the user in light of its specific status of free software,
 * that may mean  that it is complicated to manipulate,  and  that  also
 * therefore means  that it is reserved for developers  and  experienced
 * professionals having in-depth computer knowledge. Users are therefore
 * encouraged to load and test the software's suitability as regards their
 * requirements in conditions enabling the security of their systems and/or
 * data to be ensured and,  more generally, to use and operate it in the
 * same conditions as regards security.
 *
 * The fact that you are presently reading this means that you have had
 *
 * knowledge of the CeCILL-C license and that you accept its terms.
 */

/**
 * \file createNodata.cpp
 * \author Institut national de l'information géographique et forestière
 * \~french \brief Création d'une image contenant une tuile monochrome
 * \~english \brief Create an image, containing one monochrome tile
 * \~french \details Cet outil est utilisé afin de mettre à disposition du serveur WMS/WMTS des tuiles de non-donnée, au même format que les dalles de données. Toutes les composantes de l'images doivent être fournies.
 */

#include "TiledTiffWriter.h"
#include "Logger.h"
#include "Image.h"
#include "Format.h"
#include <cstdlib>
#include <iostream>
#include <string.h>
#include "tiffio.h"
#include "../be4version.h"

/**
 * \~french
 * \brief Affiche l'utilisation et les différentes options de la commande createNodata
 * \details L'affichage se fait dans la sortie d'erreur
 * \~ \code
 * createNodata version X.X.X
 *
 * Create an TIFF image, containing one monochrome tile
 *
 * Usage: createNodata -n <VAL> [-c <VAL>] -p <VAL> [-t <VAL> <VAL>] -a <VAL> -s <VAL> -b <VAL> <OUTPUT FILE>
 *
 * Parameters:
 *      -n nodata value, one interger per sample, seperated with comma. This only value will be present in the tile.
 *      -c output compression : default value : none
 *              raw     no compression
 *              none    no compression
 *              jpg     Jpeg encoding
 *              lzw     Lempel-Ziv & Welch encoding
 *              pkb     PackBits encoding
 *              zip     Deflate encoding
 *              png     Portable Network Graphics encoding (unofficial TIFF compression)
 *      -p photometric :
 *              gray    min is black
 *              rgb     for image with alpha too
 *      -t tile size : width and height. Sizes are tile and image ones. Default value : 256 256.
 *      -a sample format : uint (unsigned integer) or float
 *      -s samples per pixel : 1, 3 or 4
 *      -b bits per sample : 8 (for unsigned 8-bit integer) or 32 (for 32-bit float)
 *
 * Examples
 *      - for orthophotography
 *      createNodata -c zip -t 256 256 -s 3 -b 8 -p rgb -a uint -n 255,255,255 nodata.tif
 *
 *      - for DTM
 *      createNodata -c lzw -t 256 256 -s 1 -b 32 -p gray -a float -n -99999 nodata.tif
 * \endcode
 */
void usage() {

    LOGGER_INFO ( "\ncreateNodata version " << BE4_VERSION << "\n\n" <<

                  "Create an TIFF image, containing one monochrome tile\n\n" <<

                  "Usage: createNodata -n <VAL> [-c <VAL>] -p <VAL> [-t <VAL> <VAL>] -a <VAL> -s <VAL> -b <VAL> <OUTPUT FILE>\n\n" <<

                  "Parameters:\n" <<
                  "     -n nodata value, one interger per sample, seperated with comma. This only value will be present in the tile.\n" <<
                  "     -c output compression : default value : none\n" <<
                  "             raw     no compression\n" <<
                  "             none    no compression\n" <<
                  "             jpg     Jpeg encoding\n" <<
                  "             lzw     Lempel-Ziv & Welch encoding\n" <<
                  "             pkb     PackBits encoding\n" <<
                  "             zip     Deflate encoding\n" <<
                  "             png     Portable Network Graphics encoding (unofficial TIFF compression)\n" <<
                  "     -p photometric :\n" <<
                  "             gray    min is black\n" <<
                  "             rgb     for image with alpha too\n" <<
                  "     -t tile size : width and height. Sizes are tile and image ones. Default value : 256 256.\n" <<
                  "     -a sample format : uint (unsigned integer) or float\n" <<
                  "     -s samples per pixel : 1, 3 or 4\n" <<
                  "     -b bits per sample : 8 (for unsigned 8-bit integer) or 32 (for 32-bit float)\n\n" <<

                  "Examples\n" <<
                  "     - for orthophotography\n" <<
                  "     createNodata -c zip -t 256 256 -s 3 -b 8 -p rgb -a uint -n 255,255,255 nodata.tif\n\n" <<

                  "     - for DTM\n" <<
                  "     createNodata -c lzw -t 256 256 -s 1 -b 32 -p gray -a float -n -99999 nodata.tif\n" );
}

/**
 * \~french
 * \brief Affiche un message d'erreur, l'utilisation de la commande et sort en erreur
 * \param[in] message message d'erreur
 * \param[in] errorCode code de retour
 */
void error ( std::string message, int errorCode ) {
    LOGGER_ERROR ( message );
    usage();
    sleep ( 1 );
    exit ( errorCode );
}

/**
 ** \~french
 * \brief Fonction principale de l'outil createNodata
 * \details Tout est contenu dans cette fonction.
 * \param[in] argc nombre de paramètres
 * \param[in] argv tableau des paramètres
 * \return code de retour, 0 en cas de succès, -1 sinon
 ** \~english
 * \brief Main function for tool createNodata
 * \details All instructions are in this function.
 * \param[in] argc parameters number
 * \param[in] argv parameters array
 * \return return code, 0 if success, -1 otherwise
 */
int main ( int argc, char* argv[] ) {
    // Valeurs obligatoires
    char* output = 0;
    char* strnodata = 0;

    int photometric = -1;
    int bitspersample = -1;
    int sampleformat = -1;
    int samplesperpixel = -1;

    // Valeurs par défaut
    int imagewidth = 256, imageheight = 256;
    int compression = COMPRESSION_NONE;

    int quality = -1;

    /* Initialisation des Loggers */
    Logger::setOutput ( STANDARD_OUTPUT_STREAM_FOR_ERRORS );

    Accumulator* acc = new StreamAccumulator();
    //Logger::setAccumulator(DEBUG, acc);
    Logger::setAccumulator ( INFO , acc );
    Logger::setAccumulator ( WARN , acc );
    Logger::setAccumulator ( ERROR, acc );
    Logger::setAccumulator ( FATAL, acc );

    std::ostream &logd = LOGGER ( DEBUG );
    logd.precision ( 16 );
    logd.setf ( std::ios::fixed,std::ios::floatfield );

    std::ostream &logw = LOGGER ( WARN );
    logw.precision ( 16 );
    logw.setf ( std::ios::fixed,std::ios::floatfield );

//  Nodata image dimensions are precised in parameters and image contains a single tile

    for ( int i = 1; i < argc; i++ ) {
        if ( argv[i][0] == '-' ) {
            switch ( argv[i][1] ) {
            case 'h': // help
                usage();
                exit ( 0 );
            case 'c': // compression
                if ( ++i == argc ) error ( "Error in option -c",-1 );
                if ( strncmp ( argv[i], "none",4 ) == 0 ) compression = COMPRESSION_NONE;
                else if ( strncmp ( argv[i], "raw",3 ) == 0 ) compression = COMPRESSION_NONE;
                else if ( strncmp ( argv[i], "lzw",3 ) == 0 ) compression = COMPRESSION_LZW;
                else if ( strncmp ( argv[i], "zip",3 ) == 0 ) compression = COMPRESSION_DEFLATE;
                else if ( strncmp ( argv[i], "pkb",3 ) == 0 ) compression = COMPRESSION_PACKBITS;
                else if ( strncmp ( argv[i], "png",3 ) == 0 ) {
                    compression = COMPRESSION_PNG;
                    if ( argv[i][3] == ':' ) quality = atoi ( argv[i]+4 );
                } else if ( strncmp ( argv[i], "jpg",3 ) == 0 ) {
                    compression = COMPRESSION_JPEG;
                    if ( argv[i][4] == ':' ) quality = atoi ( argv[i]+5 );
                } else error ( "Unknown value for option -c : " + std::string ( argv[i] ),-1 );
                break;
            case 'n': // nodata
                if ( ++i == argc ) error ( "Error in option -n",-1 );
                strnodata = argv[i];
                break;
            case 'p': // photomètrie
                if ( ++i == argc ) error ( "Error in option -p",-1 );
                if ( strncmp ( argv[i], "gray",4 ) == 0 ) photometric = PHOTOMETRIC_MINISBLACK;
                else if ( strncmp ( argv[i], "rgb",3 ) == 0 ) photometric = PHOTOMETRIC_RGB;
                else error ( "Unknown value for option -p : " + std::string ( argv[i] ),-1 );
                break;
            case 't': // dimension de la tuile de nodata
                if ( i+2 >= argc ) error ( "Error in option -t",-1 );
                imagewidth = atoi ( argv[++i] );
                imageheight = atoi ( argv[++i] );
                break;
            case 'a': // format des canaux
                if ( ++i == argc ) error ( "Error in option -a",-1 );
                if ( strncmp ( argv[i],"uint",4 ) ==0 ) sampleformat = SAMPLEFORMAT_UINT;
                else if ( strncmp ( argv[i],"float",5 ) ==0 ) sampleformat = SAMPLEFORMAT_IEEEFP;
                else error ( "Unknown value for option -a : " + std::string ( argv[i] ),-1 );
                break;
            case 'b': // bitspersample
                if ( i++ >= argc ) error ( "Error in option -b",-1 );
                if ( strncmp ( argv[i], "8",1 ) == 0 ) bitspersample = 8 ;
                else if ( strncmp ( argv[i], "32",2 ) == 0 ) bitspersample = 32 ;
                else error ( "Unknown value for option -b : " + std::string ( argv[i] ),-1 );
                break;
            case 's':
                if ( ++i == argc ) error ( "Error in option -s",-1 );
                if ( strncmp ( argv[i], "1",1 ) == 0 ) samplesperpixel = 1 ;
                else if ( strncmp ( argv[i], "3",1 ) == 0 ) samplesperpixel = 3 ;
                else if ( strncmp ( argv[i], "4",1 ) == 0 ) samplesperpixel = 4 ;
                else error ( "Unknown value for option -s : " + std::string ( argv[i] ),-1 );
                break;
            default:
                error ( "Unknown option",-1 );
            }
        } else {
            if ( output == 0 ) output = argv[i];
            else error ( "We have to specify only one output file path. What is " + std::string ( argv[i] ),-1 );
        }
    }

    if ( output == 0 ) error ( "Missing output file",-1 );
    if ( strnodata == 0 ) error ( "Missing nodata value",-1 );

    if ( bitspersample == -1 ) error ( "Missing bits per sample",-1 );
    if ( sampleformat == -1 ) error ( "Missing sample format",-1 );
    if ( samplesperpixel == -1 ) error ( "Missing samples per pixel",-1 );
    if ( photometric == -1 ) error ( "Missing photometric",-1 );

    // Contrôle des compatibilité format <-> compression
    if ( photometric == PHOTOMETRIC_MINISBLACK && compression == COMPRESSION_JPEG ) error ( "Gray jpeg not supported",-1 );
    if ( samplesperpixel == 4 && compression == COMPRESSION_JPEG ) error ( "Jpeg with alpha is unconsistent",-1 );

    // Conversion string->int[] du paramètre nodata
    int nodata[samplesperpixel];
    char* charValue = strtok ( strnodata,"," );
    if ( charValue == NULL ) {
        error ( "Error with option -n : a value for nodata is missing : " + std::string ( strnodata ),-1 );
    }
    nodata[0] = atoi ( charValue );
    for ( int i = 1; i < samplesperpixel; i++ ) {
        charValue = strtok ( NULL, "," );
        if ( charValue == NULL ) {
            error ( "Error with option -n : a value for nodata is missing : " + std::string ( strnodata ),-1 );
        }
        nodata[i] = atoi ( charValue );
    }

    // input data creation : the same value (nodata) everywhere
    int bytesperpixel = samplesperpixel*bitspersample/8;
    uint8_t data[imageheight*imagewidth*bytesperpixel];

    if ( bitspersample == 32 && sampleformat == SAMPLEFORMAT_IEEEFP ) {
        // Case float32
        float nodataFloat32[samplesperpixel];
        for ( int i = 0; i < samplesperpixel; i++ ) nodataFloat32[i] = ( float ) nodata[i];

        for ( int i = 0; i<imageheight*imagewidth; i++ )
            memcpy ( data+i*bytesperpixel, nodataFloat32, bytesperpixel );
    } else if ( bitspersample == 8 && sampleformat == SAMPLEFORMAT_UINT ) {
        // Case int8
        uint8_t nodataUInt8[samplesperpixel];
        for ( int i = 0; i < samplesperpixel; i++ ) nodataUInt8[i] = ( uint8_t ) nodata[i];

        for ( int i = 0; i<imageheight*imagewidth; i++ )
            memcpy ( data+i*bytesperpixel, nodataUInt8, bytesperpixel );
    } else {
        error ( "Unknown sample type (sample format + bits per sample)",-1 );
    }

    TiledTiffWriter W ( output, imagewidth, imageheight, photometric, compression, quality, imagewidth, imageheight,bitspersample,samplesperpixel,sampleformat );

    if ( W.WriteTile ( 0, 0, data ) < 0 ) error ( "Error while writting tile of nodata",-1 );
    if ( W.close() < 0 ) error ( "Error while writting index",-1 );

    delete acc;

    return 0;
}

