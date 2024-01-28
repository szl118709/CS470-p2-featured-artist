README for Mosaic video starter code
(Thank you Andrew Zhu Aday)

The "MosaicTest.unitypackage" in this folder contains:

1) a bleeding-edge build of Chunity, containing the latest ChucK compiled 
for macOS and Windows; linux users, please contact Ge/Andrew over Discord

2) to use this, start a new **3D URP** project in UnityHub (FYI this was
tested on editor version 2020.3.26f1); in menu Assets/Import Package
-> Custom Package... choose MosaicTest.unitypackage, make sure everything
is checked, and click "import". Navigate to the Scenes folder in the project,
and choose the "MosaicTest" scene...

3) the "MosaicTest" scene that runs the demo; usage: WASD keys to move, 
left-click mouse and drag moues to look around

4) VideoManager.cs is the "glue" that binds the various parts of the 
system together; it contains video code and communication between ChucK 
and C#; it runs mosaic-synth-chunity.ck with gangnam-23.txt

5) Assets/StreamingAssets contains mosaic-synth-chunity.ck, a slightly 
modified version our mosaic synth. It maintains two global variables 
for the fileIndex and the startTime; the folder also contains the features 
file(s) and audio file(s).

6) Assets/Video contains the corresponding video file(s)

Got a question? Let us know!
