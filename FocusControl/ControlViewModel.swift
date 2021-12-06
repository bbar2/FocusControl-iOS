//
//  ViewModel.swift
//  YetAnotherTest
//
//  Created by Barry Bryant on 10/19/21.
//

import SwiftUI
import CoreBluetooth

// Define the number of focus motor micro steps for each FocusMode
enum FocusMode:Int {
  case course
  case medium
  case fine
}

class ControlViewModel : BleDelegates, ObservableObject  {

  private let FOCUS_SERVICE_UUID = CBUUID(string: "828b0000-046a-42c7-9c16-00ca297e95eb")

  @Published var statusString = "Not Connected"
  @Published var motorCommand: Int32 = 0

  public var connected = false
  public var focusMode = FocusMode.medium
  
  // Called by ViewController to initialize FocusMotorController
  func focusMotorInit(){
    bleInit()
    if (!connected) {
      statusString = "Searching for Focus-Motor ..."
      connected = true
    }
    initViewModel()
  }
  
  // Called by focusMotorInit & BleDelegates overrides on BLE Connect or Disconnect
  func initViewModel(){
    motorCommand = 0
  }

  func updateMotorCommandCW(){
    motorCommand += changeBy()
    sendBleMotorCommand(motorCommand)
  }
  
  func updateMotorCommandCCW(){
    motorCommand -= changeBy()
    sendBleMotorCommand(motorCommand)
  }

  // From C++ Hardware FocusMotor Controller:
  // 20 steps per hardware remote control encoder revolution
  // For 1 to 1 remote control knob to focus knob ratio, multiply encoder count:
  //   x 10 to get 200 ble_central steps per 20 encoder steps
  //   x sprocket ratio of 74/20 knob to motor teeth
  let fullStepsPerUiInput:Int32 = 10 * 74 / 20
  
  func changeBy() -> Int32 {
    switch (focusMode) {
    case .course:
      // Match precision of hardware remote control
      return fullStepsPerUiInput * getBleFocusMotorMicroSteps()
    case .medium:
      // Smaller steps for improved focus control - force to multiple of MicroSteps
      return fullStepsPerUiInput / 4 * getBleFocusMotorMicroSteps()
    case .fine:
      // Smallest steps for finest control.  Could go finer with single microSteps,
      // but that seems too small in practice. Go with full steps for now.
      return getBleFocusMotorMicroSteps() // one full step
    }
  }
  
  func bleInit(){
    focusMotorBleInit(service_uuid: FOCUS_SERVICE_UUID)
  }
  
  override func reportBleScanning() {
    statusString = "Scanning ..."
  }
  override func reportBleNotAvailable() {
    statusString = "BLE Not Available"
  }

  override func reportBleServiceFound(){
    statusString = "Focus Motor Found"
  }
  
  override func reportBleServiceConnected(){
    initViewModel()
    statusString = "Connected"
    connected = true
  }

  override func reportBleServiceDisconnected(){
    initViewModel()
    statusString = "Disconnected"
    connected = false
  }
  
  // Figure out how to bring this to the model, and keep this separate from the BleDelegates super class
  func sendBleMotorCommand(_ cmd:Int32) {
    focusMotorSendBleCommand(cmd)
  }
  
  // Figure out how to bring this to the model, and keep this separate from the BleDelegates super class
  override func getBleFocusMotorMicroSteps() -> Int32 {
    return super.getBleFocusMotorMicroSteps();
  }


}
