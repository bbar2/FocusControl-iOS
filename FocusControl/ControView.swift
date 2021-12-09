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
import CoreHaptics

struct ControlView: View {
  @ObservedObject var viewModel = ControlViewModel();
  @State private var engine:CHHapticEngine?

  var body: some View {
    VStack {
      
      // App Title and BLE connection status area
      // Yellow circle emulates yellow LED on hardware focus control
      Text("Focus Control").bold()
      HStack{
        Text("Status: ")
        Text(viewModel.statusString)
      }
      
      Text("").padding(50)

      // Focus mode selection and indication area
      // Red circles emulate red LEDs on hardware device.
      Text("Focus Mode").bold()
      HStack{
        Picker(selection: $viewModel.focusMode,
               label: Text("???")) {
          Text("Course").tag(FocusMode.course)
          Text("Medium").tag(FocusMode.medium)
          Text("Fine").tag(FocusMode.fine)
        }
        .pickerStyle(.segmented)
        .colorMultiply(.red) // kludge to get red
        .onTapGesture{hapticBump()}
      }
      
      Text("").padding(30)

      // Focus control area - BIG buttons simplify focusing
      // while looking through telescope and not at UI.
      Text("Adjust Focus").bold()
      let frameWidth:CGFloat = 190
      HStack {
        Button("\nCounter\nClockwise\n") {
          hapticBump()
          viewModel.updateMotorCommandCCW()}
        .frame(width:frameWidth)
        Button("\nClockwise\n\n") {
          hapticBump()
          viewModel.updateMotorCommandCW()
        }
        .frame(width:frameWidth)
      }
      .buttonStyle(.bordered)
      HStack{
        Text("Focus Command")
        Text(viewModel.motorCommand.description)
      }
    }
     
    .onAppear{
      prepareHaptics()
      viewModel.focusMotorInit()

      //Change picker font size
      UISegmentedControl.appearance().setTitleTextAttributes(
        [.font : UIFont.preferredFont(forTextStyle: .title1)],
        for: .normal)

    }.preferredColorScheme(.dark)
    .foregroundColor(.red)
    .tint(.pink)
    .controlSize(.large)
    .font(.title)
  }

  func prepareHaptics() {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    
    do {
      self.engine = try CHHapticEngine()
      try engine?.start()
    } catch {
      print("There was an error creating Haptics engine: \(error.localizedDescription)")
    }
  }
  
  func hapticBump() {
    let impact = UIImpactFeedbackGenerator(style: .heavy)
    impact.impactOccurred()
  }
}



struct MainView_Previews: PreviewProvider {
  static var previews: some View {
      ControlView()
  }
}
