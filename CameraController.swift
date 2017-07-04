//
//  CameraController.swift
//  AV Foundation
//
//  Created by suresh on 06/06/17.
//

import Foundation
import UIKit
import AVFoundation

class CameraController: NSObject {
    
    var captureSession: AVCaptureSession?
    
    var frontCamera: AVCaptureDevice?
    var rearCamera: AVCaptureDevice?
    
    var currentCameraPosition: CameraPosition?
    var frontCameraInput: AVCaptureDeviceInput?
    var rearCameraInput: AVCaptureDeviceInput?
    
    var photoOutput: AVCapturePhotoOutput?
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var flashMode = AVCaptureFlashMode.off
    
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    
    func prepare(completionHandler: @escaping (Error?) -> Void)
    {
        
        func createCaptureSession()
        {
            self.captureSession = AVCaptureSession()
        }
        
        func configreCaptureDevices() throws
        {
            //1
            let session = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaTypeVideo, position: .unspecified)
            guard let cameras = (session?.devices.flatMap { $0 }), !cameras.isEmpty else { throw CameraControllerError.noCamerasAvailable}
            //2
            for camera in cameras
            {
                if camera.position == .front
                {
                    self.frontCamera = camera
                }
                
                if camera.position == .back
                {
                    self.rearCamera = camera
                    
                    try camera.lockForConfiguration()
                    camera.focusMode = .continuousAutoFocus
                    camera.unlockForConfiguration()
                }
            }
        }
        
        func configureDeviceInputs() throws
        {
            //3
            guard let captureSession = self.captureSession else {throw CameraControllerError.capatureSessionIsMissing}
            //4
            if let rearCamera = self.rearCamera
            {
                self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                if captureSession.canAddInput(self.rearCameraInput!){captureSession.addInput(self.rearCameraInput!)}
                self.currentCameraPosition = .rear
            }
            else if let frontCamera = self.frontCamera
            {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!)}
                else { throw CameraControllerError.inputsAreInvalid}
                self.currentCameraPosition = .front
            }
            else
            {
                throw CameraControllerError.noCamerasAvailable
            }
        }
        
        func configurePhotoOutput() throws
        {
            guard let captureSession = self.captureSession else {throw CameraControllerError.capatureSessionIsMissing}
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format:[AVVideoCodecKey : AVVideoCodecJPEG])], completionHandler: nil)
            
            if captureSession.canAddOutput(self.photoOutput)
            {
                captureSession.addOutput(self.photoOutput)
            }
            
            captureSession.startRunning()
         }
        
         DispatchQueue(label: "prepare").async
         {
            do {
                 createCaptureSession()
                 try configreCaptureDevices()
                 try configureDeviceInputs()
                 try configurePhotoOutput()
               }
            
               catch
               {
                  DispatchQueue.main.async
                  {
                    completionHandler(error)
                  }
                  return
                }
            
                 DispatchQueue.main.async
                 {
                    completionHandler(nil)
                 }
         }
   }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.capatureSessionIsMissing }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    func switchCameras() throws {
        
        //5
        guard let currentCameraPosition = currentCameraPosition, let captureSession = self.captureSession, captureSession.isRunning else {throw CameraControllerError.capatureSessionIsMissing}
        //6
        captureSession.beginConfiguration()
        
        func switchToFrontCamera() throws {
            guard let inputs = captureSession.inputs as? [AVCaptureInput], let rearCameraInput = self.rearCameraInput, inputs.contains(rearCameraInput),
                let frontCamera = self.frontCamera else { throw CameraControllerError.invalidOperation }
            
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            captureSession.removeInput(rearCameraInput)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                
                self.currentCameraPosition = .front
            }
                
            else { throw CameraControllerError.invalidOperation }
        }
        func switchToRearCamera() throws {
            guard let inputs = captureSession.inputs as? [AVCaptureInput], let frontCameraInput = self.frontCameraInput, inputs.contains(frontCameraInput),
                let rearCamera = self.rearCamera else { throw CameraControllerError.invalidOperation }
            
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            captureSession.removeInput(frontCameraInput)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                
                self.currentCameraPosition = .rear
            }
                
            else { throw CameraControllerError.invalidOperation }
        }
        
        //7
        switch currentCameraPosition{
        case .front:
            try switchToRearCamera()
        case .rear:
            try switchToFrontCamera()
        }
        //8
        captureSession.commitConfiguration()
    }
    
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void){
        guard let captureSession = captureSession, captureSession.isRunning else { completion(nil, CameraControllerError.capatureSessionIsMissing); return}
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode
        
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
    
    public func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?,
                        resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Swift.Error?) {
        if let error = error { self.photoCaptureCompletionBlock?(nil, error) }
            
        else if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil),
            let image = UIImage(data: data) {
            
            self.photoCaptureCompletionBlock?(image, nil)
        }
            
        else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unKnown)
        }
    }
}

extension CameraController{
    enum CameraControllerError: Swift.Error{
        case captureSessionAlreadyRunning
        case capatureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unKnown
    }
    
    public enum CameraPosition{
        case front
        case rear
    }
}
