//
//  ViewModel.swift
//  YetAnotherTest
//
//  Created by Barry Bryant on 10/19/21.
//

import SwiftUI
enum FocusMode {
  case course
  case medium
  case fine
}

class MainViewModel : ObservableObject {
  @Published var statusString = "Not Connected"
  @Published var focusCommand = 0

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
  
  private func getDeltaFocus()->Int {
    switch(focusMode) {
    case .course:
      return 100
    case .medium:
      return 25
    case .fine:
      return 1
    }
  }
  
  func increaseFocus(){
    focusCommand += getDeltaFocus()
  }
  
  func decreaseFocus(){
    focusCommand -= getDeltaFocus()
  }
  
  func viewAppear(){
  }

  func viewDisappear(){
  }
  
}
