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
  @StateObject var viewModel = ControlViewModel()
  @Environment(\.scenePhase) var scenePhase
  
  var body: some View {
    VStack {
      
      // App Title and BLE connection status area
      // Yellow title emulates yellow LED on hardware focus control
      VStack {
        Text("Focus Control").bold()
        HStack{
          Text("Status: ")
          Text(viewModel.statusString)
        }
      }.colorMultiply(viewModel.bleIsReady() ? .red : .yellow)
      
      Spacer()
      
      VStack {
        //XLView(viewModel: viewModel)
        VStack{
          Text("XL Data").bold()
          Text("X: \(viewModel.xlData.x)")
          Text("Y: \(viewModel.xlData.y)")
          Text("Z: \(viewModel.xlData.z)")
          HStack{
            Button("Update"){
              softBump()
              viewModel.reportUiActive()
              viewModel.requestCurrentXl()
            }
            Button("Start"){
              softBump()
              viewModel.reportUiActive()
              viewModel.startXlStream()
            }
            Button("Stop"){
              softBump()
              viewModel.reportUiActive()
              viewModel.stopXlStream()
            }
          }
          HStack{
            Button("Disconnect"){
              softBump()
              viewModel.disconnect()
            }
            Button("Reconnect"){
              softBump()
              viewModel.reportUiActive()
              viewModel.reconnect()
            }
          }
        }
        
        Spacer()
        
        // Focus mode selection and indication area
        // Red circles emulate red LEDs on hardware device.
        VStack {
          Text("Focus Mode").bold()
          Picker(selection: $viewModel.focusMode,
                 label: Text("???")) {
            Text("Course").tag(FocusMode.course)
            Text("Medium").tag(FocusMode.medium)
            Text("Fine").tag(FocusMode.fine)
          } .pickerStyle(.segmented)
            .onChange(of: viewModel.focusMode) { picker in
              softBump()
              viewModel.reportUiActive()
            }
        }
        Spacer()
        
        // Focus control area - BIG buttons simplify focusing
        // while looking through telescope and not at UI.
        VStack{
          Text("Adjust Focus").bold()
          HStack {
            Button("\nCounter\nClockwise\n") {
              heavyBump() // feel different
              viewModel.reportUiActive()
              viewModel.updateMotorCommandCCW()}
            Spacer()
            Button("\nClockwise\n\n") {
              softBump()
              viewModel.reportUiActive()
              viewModel.updateMotorCommandCW()
            }
          }
        }
      } // Vstack that is always Red
      .colorMultiply(Color(red:159/255, green: 0, blue: 0))
      
    } // top level VStack
    .onChange(of: scenePhase) { newPhase in
      if newPhase == .active {
        viewModel.reconnect()
      } else if newPhase == .inactive {
        viewModel.disconnect()
      } else if newPhase == .background {
        viewModel.disconnect()
      }
    }
    .preferredColorScheme(.dark)
    .foregroundColor(.white)
    .buttonStyle(.bordered)
    .controlSize(.large)
    .font(.title)
    
    .onAppear{
      viewModel.focusMotorInit()
      
      //Change picker font size
      UISegmentedControl.appearance().setTitleTextAttributes(
        [.font : UIFont.preferredFont(forTextStyle: .title1)],
        for: .normal)
    }
    .onShake {
      viewModel.reconnect()
    }
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
