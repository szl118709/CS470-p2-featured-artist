//---------------------------------------------------------------------
// name: mosaic_video.pde
// desc: mosAIc video player
//
// usage: to be run with the audio mosAIc in ChucK
//        mosaic-synth.ck -- sends OSC messages (video and startTime)
//        mosaic-synth-key.ck -- the above with keyboard controls
//
// author: Ge Wang
// date: spring 2023
//---------------------------------------------------------------------
//import processing.video.*;
import oscP5.*;
import netP5.*;

// open sound control
OscP5 oscP5;
// picture of fish
PImage img;
float img_size = 50;

// variables for managing incoming control data
boolean updateRecv = true;
int curr_beat = 0;
float num_beats = 10;

// initialization function (called by Processing)
void setup()
{
  // set window title
  surface.setTitle("audio mosAIc | video player");
  // make window resizable
  surface.setResizable( true );
  // canvas size
  size(1280, 720);
  
  // load picture
  img = loadImage("data/mug.PNG");

  // set up open sound control for listening
  setupOSC( 12000 );
}

// set up open sound control for listening
void setupOSC( int port )
{
    // start oscP5, listening for incoming messages at port 12000
    oscP5 = new OscP5( this, port );
}

// render one frame (called by Processing)
void draw()
{  
    background(255);
 
    // if received update
    if( updateRecv )
    {
        // set to falst until next incoming message
        updateRecv = false;
    }
    
    // draw
    for (int i = 1; i <= curr_beat; i++) {
      if (width*i/(num_beats+1) < width - img_size) {
        image(img, width*i/(num_beats+1) - img_size/2, height/2, img_size, img_size);
      }
    }
}


// incoming osc message are forwarded to the oscEvent method.
void oscEvent(OscMessage theOscMessage)
{
  if( theOscMessage.checkAddrPattern("/mosaic/window")==true )
  {
    // check if the typetag is the right one
    if(theOscMessage.checkTypetag("if"))
    {
      // set flag
      updateRecv = true;
      // parse theOscMessage and extract the values from the osc message arguments.
      curr_beat = theOscMessage.get(0).intValue();  
      num_beats = theOscMessage.get(1).floatValue();
      //println(" values: "+curr_beat+", "+num_beats);
      return;
    }  
  } 
}
