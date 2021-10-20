//
//  ViewModel.swift
//  YetAnotherTest
//
//  Created by Barry Bryant on 10/19/21.
//

import SwiftUI

// Define the number of focus motor steps for each FocusMode
enum FocusMode:Int {
  case course = 100
  case medium = 25
  case fine   = 1
}

class MainViewModel : ObservableObject {

  @Published var statusString = "Not Connected"
  @Published var focusMotorCommand = 0

  public var connected = false
  public var focusMode = FocusMode.medium
  
  // Start looking for BLE peripheral
  func beginBle(){
    statusString = "Searching ..."
    connected = true
  }
  
  func endBle(){
    statusString = "Not Connected"
    connected = false
  }
  
  func increaseFocus(){
    focusMotorCommand += focusMode.rawValue
  }
  
  func decreaseFocus(){
    focusMotorCommand -= focusMode.rawValue
  }
  
  func viewAppear(){
  }

  func viewDisappear(){
  }
  
}
