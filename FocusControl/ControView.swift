//
//  ContentView.swift
//  FocusControl
//
//  Created by Barry Bryant on 10/19/21 - iOS UI to control a telescope focus
// motor.  The focus-motor is attached to the manual focus knob on a telescope.
// The UI is sized for an iPhone, or a half screen iPad.  The iPad use case
// anticipates use in parallel with a separate app (other half screen) to
// control telescope pointing.
//
//   The focus-motor is controlled by a Blue Tooth Low Energy (BLE) interface.
// In BLE parlance, the focus-motor is a BLE Peripheral (aka Server), and the
// remote control is a BLE Central (aka Client). The focus-motor BLE interface
// exposes one service with one writable data value, commanded motor position,
// which this BLE Central app updates via two focus buttons.  One button turns
// the focus-motor clockwise, the other turns the focus-motor counter clockwise.
//
//   This app can be uses as an alternative to the hardware remote control
// which uses a rotating knob to control focus, a yellow LED to inidcate a lack
// of a BLE connection, and two red LEDs to indicate focus mode.
//
//  The app runs in three diferent focus modes, determined by a selector on
// the UI.
// Course Mode - Turn the focus-motor MANY micro steps per button press.  Used
//               for course initial focusing, to get in the ball park.
//               Course Mode is indicated by both red LEDs off.
// Medium Mode - Turn the focus-motor MANY/4 micro steps per button press. Used
//               for more precise focusing. Indicated by one red LED on.
// Fine Mode - Turn the focus-motor 1 micro step per button press.  The
//             smallestadjustments possible. Indicated by both red LEDs on.
//
// The BLE connection process is initiated when the GUI appears.  The yellow
// indicator remains yellow until the BLE connection is complete. The BLE
// connection is released when the GUI disappears.  The yellow indictator
// on the UI indicates mirrors the function of the yellow LED on the hardware
// remote control device.
//

import SwiftUI

struct ControlView: View {
  @ObservedObject var viewModel = ControlViewModel();

  var body: some View {
    VStack {
      
      // App Title and BLE connection status area
      // Yellow circle emulates yellow LED on hardware focus control
      Text("Focus Control")
      HStack{
        Text("Status: ")
        Text(viewModel.statusString)
      }
      Text("").padding()

      // Focus mode selection and indication area
      // Red circles emulate red LEDs on hardware device.
      Text("Focus Mode")
      HStack{
        Picker(selection: $viewModel.focusMode,
               label: Text("Focus Mode")) {
          Text("Course").tag(FocusMode.course)
          Text("Medium").tag(FocusMode.medium)
          Text("Fine").tag(FocusMode.fine)
        }
        .pickerStyle(.segmented)
        .padding()
      }
      Text("").padding()

      // Focus control area - BIG buttons simplify focusing
      // while looking through telescope and not at UI.
      Text("Adjust Focus")
      HStack {
        Button("\n FOCUS \n\n CCW \n",
               action:{viewModel.updateMotorCommandCCW()})
        Button("\n FOCUS \n\n CW \n",
               action:{viewModel.updateMotorCommandCW()})
      }.buttonStyle(.bordered)
      HStack{
        Text("Focus Command")
        Text(viewModel.motorCommand.description)
      }
    }

    .onAppear{
      viewModel.focusMotorInit()
    }
    
    .onDisappear{
//      viewModel.focusMotorClose()
    }

  }

}

struct MainView_Previews: PreviewProvider {
  static var previews: some View {
      ControlView()
  }
}
