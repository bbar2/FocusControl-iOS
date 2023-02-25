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
  @ObservedObject var viewModel = ControlViewModel()
   
  var body: some View {
    VStack {
      
      // App Title and BLE connection status area
      // Yellow circle emulates yellow LED on hardware focus control
      Text("Focus Control").bold()
      HStack{
        Text("Status: ")
        Text(viewModel.statusString)
      }
      
      Spacer()

      // Focus mode selection and indication area
      // Red circles emulate red LEDs on hardware device.
      Text("Focus Mode").bold()
      Picker(selection: $viewModel.focusMode,
             label: Text("???")) {
        Text("Course").tag(FocusMode.course)
        Text("Medium").tag(FocusMode.medium)
        Text("Fine").tag(FocusMode.fine)
      }
      .pickerStyle(.segmented)
      
      Spacer()

      // Focus control area - BIG buttons simplify focusing
      // while looking through telescope and not at UI.
      Text("Adjust Focus").bold()
      HStack {
        Button("\nCounter\nClockwise\n") {
          heavyBump()
          viewModel.updateMotorCommandCCW()}
        Spacer()
        Button("\nClockwise\n\n") {
          softBump()
          viewModel.updateMotorCommandCW()
        }
      }
      .foregroundColor(.white)
      .buttonStyle(.bordered)
    }
     
    .onAppear{
      viewModel.focusMotorInit()

      //Change picker font size
      UISegmentedControl.appearance().setTitleTextAttributes(
        [.font : UIFont.preferredFont(forTextStyle: .title1)],
        for: .normal)

    }.preferredColorScheme(.dark)
    .controlSize(.large)
    .font(.title)
    .colorMultiply(.red) // turn all whites to reds
  }
  
  func heavyBump(){
    let haptic = UIImpactFeedbackGenerator(style: .heavy)
    haptic.impactOccurred()
  }
  
  func softBump(){
    let haptic = UIImpactFeedbackGenerator(style: .soft)
    haptic.impactOccurred()
  }

}


struct MainView_Previews: PreviewProvider {
  static var previews: some View {
      ControlView()
      .previewDevice(PreviewDevice(rawValue: "iPhone Xs"))
  }
}
