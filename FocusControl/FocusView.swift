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

struct FocusView: View {
//  @ObservedObject var guideModel: GuideModel
  @ObservedObject var armModel: ArmAccelModel
  
  @StateObject var viewModel = FocusViewModel()
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
        if viewModel.bleIsReady() {
          HStack{
            Button("Disconnect"){
              softBump()
              viewModel.disconnectBle()
            }
            if viewModel.connectionLock {
              Button(){
                softBump()
                viewModel.connectionLock = false
                viewModel.reportUiActive()
              } label: {
                Image(systemName: "timer") // current state no timer
              }
            } else {
              Button(){
                softBump()
                viewModel.connectionLock = true
                viewModel.reportUiActive()
              } label: {
                Text(String(viewModel.timerValue))
              }
            }
          }
        } else {
          Button("Connect"){
            softBump()
            viewModel.connectBle()
            viewModel.reportUiActive()
          }
        }
      }.colorMultiply(viewModel.bleIsReady() ? .red : .yellow)
      
      Spacer()
      
      // Everything else is in this VStack and is red
      VStack {
        VStack{
          Text("XL Data").bold()
          Text(String(format: "Pitch: %+7.2fº %+5.2f",
                      viewModel.pitch,
                      viewModel.rhsXlData.x))
          Text(String(format: "Roll: %+7.2fº %+5.2f",
                      viewModel.roll,
                      viewModel.rhsXlData.y))
          Text(String(format: "Yaw: %+7.2fº %+5.2f",
                      viewModel.yaw,
                      viewModel.rhsXlData.z))
//          Text(String(format: "Ay: %+5.2f", viewModel.xlData.y))
//          Text(String(format: "Ax: %+5.2f", viewModel.xlData.x))
//          Text(String(format: "Az: %+5.2f", viewModel.xlData.z))
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
        viewModel.connectBle()
      } else if newPhase == .inactive {
        viewModel.disconnectBle()
      } else if newPhase == .background {
        viewModel.disconnectBle()
      }
    }
    .preferredColorScheme(.dark)
    .foregroundColor(.white)
    .buttonStyle(.bordered)
    .controlSize(.large)
    .font(.title)
    
    .onAppear{
      // pass in a reference to the ArmAccel
      viewModel.viewModelInit(linkToArmAccelModel: armModel)
      
      //Change picker font size
      UISegmentedControl.appearance().setTitleTextAttributes(
        [.font : UIFont.preferredFont(forTextStyle: .title1)],
        for: .normal)
    }
    .onShake {
      viewModel.connectBle()
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
  static let previewArmModel = ArmAccelModel()
  static var previews: some View {
    FocusView(armModel: previewArmModel)
      .previewDevice(PreviewDevice(rawValue: "iPhone Xs"))
  }
}
