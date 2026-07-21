Modify the xavier nx portions of thise project to be able to be used on the JETSON AGX ORIN
    - select GPIO pins to use
    - connect 1pps output from GPS
    - verify gps 1pps is seen by the AGX ORin 

1. Select a GPIO pin to use
2. Connect GPS 1PP output to the ORIN pins
3. verify signal is seen by the ORIN 

Verify K timer is disabled

Verify no other clock services are active, deactivate if necessary


Device tree overlay
- modify existing xavier dts to match the xavier pinout and GPIO chip specs
- Build dbo and transfer to device, ensure that github action inlcudes the new branch
- verify XAVIER can see the 1pps signal and it is mapped correctly

Udev rules
- create an appropriate udev rule for the xavier
- Ensure that the container can access the 1PPS GPS signal
- verify that the udev rule works no matter what order the usb devices are plugged in

GPS 


Update REadme

Create a step by step guide for implementation of the gpsd-chrony container from a fresh jetson agx orin install of jetson 6.x 
