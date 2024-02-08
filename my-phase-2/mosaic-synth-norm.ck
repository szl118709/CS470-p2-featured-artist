//------------------------------------------------------------------------------
// name: mosaic-synth-mic.ck (v1.3)
// desc: basic structure for a feature-based synthesizer
//       this particular version uses microphone as live input
//       and takes an optional min/max file for normalization
//
// version: need chuck version 1.4.2.1 or higher
// sorting: part of ChAI (ChucK for AI)
//
// USAGE: run with INPUT model file
//        > chuck mosaic-synth-mic-norm.ck:INPUT:DRIVER:MINMAX:DRIVER_MINMAX
// For Photosynthetic Fish, run 
// chuck mosaic-synth-norm.ck:data/PF.txt:data/deep_blue.wav:data/PF-minmax.txt:data/DB-minmax.txt
//
// date: Spring 2024
// authors: Ge Wang (https://ccrma.stanford.edu/~ge/)
//          Yikai Li
//          Samantha Liu
//------------------------------------------------------------------------------

// INPUT: pre-extracted model file; does not need to be normalized
string FEATURES_FILE;
// DRIVER: audio file
string DRIVER_AUDIO_FILE;
// MINMAX: (optional) file containing the min/max to normalize/map to for each dimension
string MINMAX_FILE;
// DRIVER_MINMAX: (optional, but has to exist if MINMAX exists) file containing min/max for the driver
string DRIVER_MINMAX_FILE;
// if have arguments, override filename
if( me.args() > 0 )
{
    me.arg(0) => FEATURES_FILE;
    me.arg(1) => DRIVER_AUDIO_FILE;
    // more?
    if( me.args() > 2 )
    {
        me.arg(2) => MINMAX_FILE;
        me.arg(3) => DRIVER_MINMAX_FILE;
    }
}
else
{
    // print usage
    <<< "usage: chuck mosaic-synth-mic.ck:INPUT:DRIVER:MINMAX:DRIVER_MINMAX", "" >>>;
    <<< " |- INPUT: model file (.txt) containing extracted feature vectors", "" >>>;
    <<< " |- DRIVER: driver file (.wav) of audio", "" >>>;
    <<< " |- MINMAX: min/max file (.txt) containing min/max for each dimension", "" >>>;
    <<< " |- DRIVER_MINMAX: min/max file (.txt) for the driver", "" >>>;
}
//------------------------------------------------------------------------------
// expected model file format; each VALUE is a feature value
// (feel free to adapt and modify the file format as needed)
//------------------------------------------------------------------------------
// filePath windowStartTime VALUE VALUE ... VALUE
// filePath windowStartTime VALUE VALUE ... VALUE
// ...
// filePath windowStartTime VALUE VALUE ... VALUE
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// expected min/max file format: each line is the min and max for a dimension
//------------------------------------------------------------------------------
// MIN1 MAX1
// MIN2 MAX2
// ...
// MIN_N MAX_N
//------------------------------------------------------------------------------



//------------------------------------------------------------------------------
// unit analyzer network: *** this must match the features in the features file
//------------------------------------------------------------------------------
// audio input into a FFT
SndBuf input => FFT fft;
// adc => FFT fft;
// a thing for collecting multiple features into one vector
FeatureCollector combo => blackhole;
// add spectral feature: Centroid
fft =^ Centroid centroid =^ combo;
// chroma 
fft =^ Chroma chroma =^ combo;
// add spectral feature: Flux
fft =^ Flux flux =^ combo;
// kurtosis
fft =^ Kurtosis kurtosis =^ combo;
// add spectral feature: MFCC
fft =^ MFCC mfcc =^ combo;
// add spectral feature: RMS
fft =^ RMS rms =^ combo;
// rolloff
fft =^ RollOff roff50 =^ combo;
fft =^ RollOff roff85 =^ combo;


//-----------------------------------------------------------------------------
// setting analysis parameters -- also should match what was used during extration
//-----------------------------------------------------------------------------
// set number of coefficients in MFCC (how many we get out)
// 13 is a commonly used value
20 => mfcc.numCoeffs;
// set number of mel filters in MFCC
10 => mfcc.numFilters;

// do one .upchuck() so FeatureCollector knows how many total dimension
combo.upchuck();
// get number of total feature dimensions
combo.fvals().size() => int NUM_DIMENSIONS;

// set FFT size
4096 => fft.size;
// set window type and size
Windowing.hann(fft.size()) => fft.window;
// our hop size (how often to perform analysis)
180.0 => float BPM;
// prompt
ConsoleInput in;
string prompt;
"Enter the desired BPM: " => prompt;
in.prompt( prompt ) => now;
Std.atoi(in.getLine()) => BPM;
(60.0/BPM)::second => dur HOP;
// how many frames to aggregate before averaging?
// (this does not need to match extraction; might play with this number)
10 => int NUM_FRAMES;
// how much time to aggregate features for each file
HOP * NUM_FRAMES => dur EXTRACT_TIME;

//------------------------------------------------------------------------------
// setting up our synthesized audio input to be analyzed and mosaic'ed
//------------------------------------------------------------------------------
// if we want to hear our audio input
input => Gain g => Delay delay => dac.left;
// add artificial delay for time alignment to mosaic output
EXTRACT_TIME + HOP=> delay.max => delay.delay;
// scale the volume
0.5 => g.gain;

// load sound (by default it will start playing from SndBuf)
DRIVER_AUDIO_FILE => input.read;
chout <= "Photosynthetic Fish, as driven by Deep Blue"; 
chout <= IO.newline();; chout.flush();


//------------------------------------------------------------------------------
// unit generator network: for real-time sound synthesis
//------------------------------------------------------------------------------
// how many max at any time?
1 => int NUM_VOICES;
// a number of audio buffers to cycel between
SndBuf buffers[NUM_VOICES]; ADSR envs[NUM_VOICES]; Pan2 pans[NUM_VOICES];
// set parameters
for( int i; i < NUM_VOICES; i++ )
{
    // connect audio
    // buffers[i] => envs[i] => pans[i] => dac;
    buffers[i] => envs[i] /*=> pans[i]*/ => Delay out_delay => dac.right;
    HOP => out_delay.max => out_delay.delay;
    // set chunk size (how to to load at a time)
    // this is important when reading from large files
    // if this is not set, SndBuf.read() will load the entire file immediately
    fft.size() => buffers[i].chunks;
    // randomize pan
    Math.random2f(-.75,.75) => pans[i].pan;
    // set envelope parameters
    envs[i].set( EXTRACT_TIME, EXTRACT_TIME/2, 1, EXTRACT_TIME );
}


//------------------------------------------------------------------------------
// load feature data; read important global values like numPoints and numCoeffs
//------------------------------------------------------------------------------
// values to be read from file
0 => int numPoints; // number of points in data
0 => int numCoeffs; // number of dimensions in data
// file read PART 1: read over the file to get numPoints and numCoeffs
loadFile( FEATURES_FILE ) @=> FileIO @ fin;
// check
if( !fin.good() ) me.exit();
// check dimension at least
if( numCoeffs != NUM_DIMENSIONS )
{
    // error
    <<< "[error] expecting:", NUM_DIMENSIONS, "dimensions; but features file has:", numCoeffs >>>;
    // stop
    me.exit();
}

false => int DO_NORMALIZE; // whether to normalize
float fishMin[NUM_DIMENSIONS]; // array reference for mins
float fishMax[NUM_DIMENSIONS]; // array reference for maxs
// load min/max for each dimension
if( loadMinMaxFile( MINMAX_FILE, fishMin, fishMax ) )
{
    // set flag
    true => DO_NORMALIZE;
}

float driverMin[NUM_DIMENSIONS]; // array reference for mins
float driverMax[NUM_DIMENSIONS]; // array reference for maxs
if( !loadMinMaxFile( DRIVER_MINMAX_FILE, driverMin, driverMax ) )
{
    // error
    <<< "[error] failed to load driver minmax from", DRIVER_MINMAX_FILE >>>;
}


//------------------------------------------------------------------------------
// each Point corresponds to one line in the input file, which is one audio window
//------------------------------------------------------------------------------
class AudioWindow
{
    // unique point index (use this to lookup feature vector)
    int uid;
    // which file did this come file (in files arary)
    int fileIndex;
    // starting time in that file (in seconds)
    float windowTime;
    
    // set
    fun void set( int id, int fi, float wt )
    {
        id => uid;
        fi => fileIndex;
        wt => windowTime;
    }
}

// array of all points in model file
AudioWindow windows[numPoints];
// unique filenames; we will append to this
string files[0];
// map of filenames loaded
int filename2state[0];
// feature vectors of data points
float inFeatures[numPoints][numCoeffs];
// generate array of unique indices
int uids[numPoints]; for( int i; i < numPoints; i++ ) i => uids[i];
// // uid of the silent sample; when this sample is detected randomly play stuff
// numPoints - 1 => int SILENCE;

// use this for new input
float features[NUM_FRAMES][numCoeffs];
// average values of coefficients across frames
float featureMean[numCoeffs];


//------------------------------------------------------------------------------
// read the data
//------------------------------------------------------------------------------
readData( fin );


//------------------------------------------------------------------------------
// set up our KNN object to use for classification
// (KNN2 is a fancier version of the KNN object)
// -- run KNN2.help(); in a separate program to see its available functions --
//------------------------------------------------------------------------------
KNN2 knn;
// k nearest neighbors
1 => int K;
// results vector (indices of k nearest points)
int knnResult[K];
// knn train
knn.train( inFeatures, uids );

// used to rotate sound buffers
0 => int which;


//------------------------------------------------------------------------------
// processing stuff
//------------------------------------------------------------------------------
// destination host name
"localhost" => string hostname;
// destination port number
12000 => int port;

// sender object
OscOut xmit;

// aim the transmitter at destination
xmit.dest( hostname, port );

// send OSC message: current file index and startTime, uniquely identifying a window
fun void sendWindow( int curr_beat, float num_beats )
{
    // start the message...
    xmit.start( "/mosaic/window" );
    
    // add int argument
    curr_beat => xmit.add;
    // add float argument
    num_beats => xmit.add;
    // send it
    xmit.send();
}


//------------------------------------------------------------------------------
// wait on keyboard
//------------------------------------------------------------------------------
// which keyboard to open (chuck --probe to available)
0 => int KB_DEVICE;
Hid hid;
HidMsg msg;

// open keyboard (get device number from command line)
if( !hid.openKeyboard( KB_DEVICE ) ) me.exit();
<<< "keyboard '" + hid.name() + "' ready", "" >>>;

spork ~ kb();

fun void kb()
{
    // infinite event loop
    while( true )
    {
        // wait on event
        hid => now;
        
        // get one or more messages
        while( hid.recv( msg ) )
        {
            // check for action type
            if( msg.isButtonDown() ) // button down
            {
                // <<< "down:", msg.which, "(code)", msg.key, "(usb key)", msg.ascii, "(ascii)" >>>;
                if( msg.ascii >= 49 && msg.ascii <= 57 ) // 1-9
                {
                    msg.ascii - 48 => NUM_FRAMES;
                }
                if ( msg.ascii ==48 ) // 0 
                {
                    10 => NUM_FRAMES;
                }
                HOP * NUM_FRAMES => dur EXTRACT_TIME;
                chout <= IO.newline();
            }
        }
    }
}


//------------------------------------------------------------------------------
// SYNTHESIS!!
// this function is meant to be sporked so it can be stacked in time
//------------------------------------------------------------------------------
fun void synthesize( int closest, int uid )
{
    // get the buffer to use
    buffers[which] @=> SndBuf @ sound;
    // get the envelope to use
    envs[which] @=> ADSR @ envelope;
    // increment and wrap if needed
    which++; if( which >= buffers.size() ) 0 => which;

    // get a referencde to the audio fragment to synthesize
    windows[uid] @=> AudioWindow @ win;
    // get filename
    files[win.fileIndex] => string filename;
    // load into sound buffer
    filename => sound.read;
    // playback rate
    (BPM / 180.0) => sound.rate;
    // seek to the window start time
    ((win.windowTime::second)/samp) $ int => sound.pos;

    // print what we are about to play
    chout <= "closest: " <= closest <= " "; chout.flush();
    chout <= "synthsizing window: ";
    // print label
    chout <= win.uid <= "["
          <= win.fileIndex <= ":"
          <= win.windowTime <= ":POSITION="
          <= sound.pos() <= "]";
    // endline
    chout <= IO.newline();

    // open the envelope, overlap add this into the overall audio
    envelope.keyOn();
    // wait
    for( int frame; frame < NUM_FRAMES; frame++ )
    {
        // chout <= frame+1 <= " "; chout.flush();
        HOP => now;
        sendWindow(frame+1, NUM_FRAMES * 1.0);
    }
    (EXTRACT_TIME*2)-envelope.releaseTime() => now;
    // start the release
    envelope.keyOff();
    // wait
    envelope.releaseTime() => now;
}


//------------------------------------------------------------------------------
// real-time similarity retrieval loop
//------------------------------------------------------------------------------
while( true )
{
    // aggregate features over a period of time
    for( int frame; frame < NUM_FRAMES; frame++ )
    {
        //-------------------------------------------------------------
        // a single upchuck() will trigger analysis on everything
        // connected upstream from combo via the upchuck operator (=^)
        // the total number of output dimensions is the sum of
        // dimensions of all the connected unit analyzers
        //-------------------------------------------------------------
        combo.upchuck();  
        // get features
        for( int d; d < NUM_DIMENSIONS; d++) 
        {
            // store them in current frame
            combo.fval(d) => features[frame][d];
        }
        // advance time
        // chout <= frame+1 <= " "; chout.flush();
        HOP => now;
    }
    chout <= IO.newline(); chout.flush();

    // compute means for each coefficient across frames
    for( int d; d < NUM_DIMENSIONS; d++ )
    {
        // zero out
        0.0 => featureMean[d];
        // loop over frames
        for( int j; j < NUM_FRAMES; j++ )
        {
            // add
            features[j][d] +=> featureMean[d];
        }
        // average
        NUM_FRAMES /=> featureMean[d];
    }
    
    // normalize
    if( DO_NORMALIZE ) normalize( featureMean );
    
    //-------------------------------------------------
    // search using KNN2; results filled in knnResults,
    // which should the indices of k nearest points
    //-------------------------------------------------
    knn.search( featureMean, K, knnResult );
    spork ~ synthesize( knnResult[0], knnResult[Math.random2(0,knnResult.size()-1)] );
}
//------------------------------------------------------------------------------
// end of real-time similiarity retrieval loop
//------------------------------------------------------------------------------


//------------------------------------------------------------------------------'
// function: normalize a vector to the min/max for each dimension
//------------------------------------------------------------------------------
fun void normalize( float v[] )
{
    // make sure we are on the level
    if( v.size() != fishMin.size() )
    {
        <<< "normalize(): dimension mismatch -- expecting", v.size(), "but min/max has", fishMin.size() >>>;
        return;
    }
    
    for( int i; i < v.size(); i++ )
    {
        // map with the ability go beyond the min/max bound
        // map the driver input (driverMin, driverMax) to (fishMin, fishMax)
        Math.map( v[i], driverMin[i], driverMax[i], fishMin[i], fishMax[i] ) => v[i];
    }
}


//------------------------------------------------------------------------------
// function: load data file
//------------------------------------------------------------------------------
fun FileIO loadFile( string filepath )
{
    // reset
    0 => numPoints;
    0 => numCoeffs;
    
    // load data
    FileIO fio;
    if( !fio.open( filepath, FileIO.READ ) )
    {
        // error
        <<< "cannot open file:", filepath >>>;
        // close
        fio.close();
        // return
        return fio;
    }
    
    string str;
    string line;

    // read the first non-empty line of features
    while( fio.more() )
    {
        // read each line
        fio.readLine().trim() => str;
        // check if empty line
        if( str != "" )
        {
            numPoints++;
            str => line;
        }
    }
    
    // a string tokenizer
    StringTokenizer tokenizer;
    // set to last non-empty line
    tokenizer.set( line );
    // negative (to account for filePath windowTime)
    -2 => numCoeffs;
    // see how many, including label name
    while( tokenizer.more() )
    {
        tokenizer.next();
        numCoeffs++;
    }
    
    // see if we made it past the initial fields
    if( numCoeffs < 0 ) 0 => numCoeffs;
    
    // check
    if( numPoints == 0 || numCoeffs <= 0 )
    {
        <<< "no data in file:", filepath >>>;
        fio.close();
        return fio;
    }
    
    // print
    <<< "# of data points:", numPoints, "dimensions:", numCoeffs >>>;
    
    // done for now
    return fio;
}


//------------------------------------------------------------------------------
// function: load data file
//------------------------------------------------------------------------------
fun int loadMinMaxFile( string filepath, float mins[], float maxs[] )
{
    // if empty, return false with no error since min/max file is optional
    if( filepath == "" ) return false;
    
    // output
    <<< "normalizing to min/max:", filepath >>>;

    // load data
    FileIO fio;
    if( !fio.open( filepath, FileIO.READ ) )
    {
        // error
        <<< "cannot open min/max file:", filepath >>>;
        // close
        fio.close();
        // return
        return false;
    }
    
    string line;
    int d;
    // a string tokenizer
    StringTokenizer tokenizer;

    // read the first non-empty line
    while( fio.more() )
    {
        // read each line
        fio.readLine().trim() => line;
        // check if empty line
        if( line != "" )
        {
            // set to last non-empty line
            tokenizer.set( line );
            // set to two values
            if( tokenizer.more() )
            {
                // min
                tokenizer.next() => Std.atof => mins[d];
                // more?
                if( tokenizer.more() )
                {
                    // max
                    tokenizer.next() => Std.atof => maxs[d];
                }
            }
            
            // increment
            d++;
        }
    }
    
    // done for now
    return true;
}


//------------------------------------------------------------------------------
// function: read the data
//------------------------------------------------------------------------------
fun void readData( FileIO fio )
{
    // rewind the file reader
    fio.seek( 0 );
    
    // a line
    string line;
    // a string tokenizer
    StringTokenizer tokenizer;
    
    // points index
    0 => int index;
    // file index
    0 => int fileIndex;
    // file name
    string filename;
    // window start time
    float windowTime;
    // coefficient
    int c;
    
    // read the first non-empty line
    while( fio.more() )
    {
        // read each line
        fio.readLine().trim() => line;
        // check if empty line
        if( line != "" )
        {
            // set to last non-empty line
            tokenizer.set( line );
            // file name
            tokenizer.next() => filename;
            // window start time
            tokenizer.next() => Std.atof => windowTime;
            // have we seen this filename yet?
            if( filename2state[filename] == 0 )
            {
                // make a new string (<< appends by reference)
                filename => string sss;
                // append
                files << sss;
                // new id
                files.size() => filename2state[filename];
            }
            // get fileindex
            filename2state[filename]-1 => fileIndex;
            // set
            windows[index].set( index, fileIndex, windowTime );

            // zero out
            0 => c;
            // for each dimension in the data
            repeat( numCoeffs )
            {
                // read next coefficient
                tokenizer.next() => Std.atof => inFeatures[index][c];
                // increment
                c++;
            }
            
            // increment global index
            index++;
        }
    }
}
