//
//  ContentView.swift
//  FocusControl
//
// Telescope Focus UI simulates FocusMotor hardware remote control's rotary
// encoder knob using two UI buttons to drive the FocusMotor clockwise (CW) or
// counter clockwise (CCW).
//
// Also provides controls to switch focus control mode between Coarse, Medium,
// and Fine modes.  Coarse mode moves the FocusMotor the most per UI operation,
// providing an initial coarse level of focus control.  Fine mode moves the
// FocusMotor in very small steps providing the finest level of focus control.
// Medium mode is in the middle.
//
// FocusMotorController transmits FocusMotor commands via Bluetooth Low
// Energy (BLE). UI status message field shows state of BLE connection.


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
