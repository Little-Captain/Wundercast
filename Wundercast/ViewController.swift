/*
 * Copyright (c) 2014-2016 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import RxSwift
import RxCocoa
import MapKit
import CoreLocation

class ViewController: UIViewController {
    
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var mapButton: UIButton!
    @IBOutlet weak var geoLocationButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var searchCityName: UITextField!
    @IBOutlet weak var tempLabel: UILabel!
    @IBOutlet weak var humidityLabel: UILabel!
    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var cityNameLabel: UILabel!
    @IBOutlet weak var tempSwitch: UISwitch!
    
    let bag = DisposeBag()
    let locationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        style()
        
        mapButton
            .rx.tap
            .subscribe(onNext: {
                self.mapView.isHidden = !self.mapView.isHidden
            })
            .disposed(by: bag)
        
        let geoInput = geoLocationButton
            .rx.tap.asObservable()
            .do(onNext: {
                self.locationManager.requestWhenInUseAuthorization()
                self.locationManager.startUpdatingLocation()
            })
        
        let currentLocation = locationManager
            .rx.didUpdateLocations
            .map { $0[0] }
            .filter { $0.horizontalAccuracy < kCLLocationAccuracyHundredMeters }
            .do(onNext: { _ in
                // 定位后需要停止, 不然没法再次定位
                self.locationManager.stopUpdatingLocation()
            })
        
        let geoLocation = geoInput.flatMap { currentLocation.take(1) }
        
        // 定位城市 -> 网络结果 Observable
        let geoSearch = geoLocation
            .flatMapLatest {
                ApiController.shared
                    .currentWeather(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude)
                    .catchErrorJustReturn(.dummy)
        }
        
        geoSearch
            .asDriver(onErrorJustReturn: .dummy)
            .map { $0.coordinate }
            .drive(mapView.rx.location)
            .disposed(by: bag)
        
        // 有效的搜索文本 Observable
        let searchInput = searchCityName
            .rx.controlEvent(.editingDidEndOnExit).asObservable()
            .withLatestFrom(searchCityName.rx.text)
            .filter { ($0 ?? "").count > 0 }
            .map { $0! }
        
        // 地图中心位置 Observable
        let mapInput = mapView
            .rx.regionDidChangeAnimated
            .skip(1)
            .map { _ in self.mapView.centerCoordinate }
        
        // 搜索文本 -> 网络结果 Observable
        let textSearch = searchInput
            .flatMapLatest { ApiController.shared.currentWeather(city: $0).catchErrorJustReturn(.dummy) }
        
        textSearch
            .asDriver(onErrorJustReturn: .dummy)
            .map { $0.coordinate }
            .drive(mapView.rx.location)
            .disposed(by: bag)
        
        let mapSearch = mapInput
            .flatMapLatest {
                ApiController.shared
                    .currentWeather(lat: $0.latitude, lon: $0.longitude)
                    .catchErrorJustReturn(.dummy)
        }
        
        let search = Observable
            .from([geoSearch, textSearch, mapSearch])
            .merge()
            .asDriver(onErrorJustReturn: .dummy)
        
        // 网络请求状态 Observable
        let running = Observable
            .from([searchInput.map { _ in true },
                   geoInput.map { _ in true },
                   mapInput.map { _ in true },
                   search.map { _ in false}.asObservable()])
            .merge()
            .startWith(true)
            .asDriver(onErrorJustReturn: false)
        
        running.skip(1).drive(activityIndicator.rx.isAnimating).disposed(by: bag)
        running.drive(tempLabel.rx.isHidden).disposed(by: bag)
        running.drive(iconLabel.rx.isHidden).disposed(by: bag)
        running.drive(humidityLabel.rx.isHidden).disposed(by: bag)
        running.drive(cityNameLabel.rx.isHidden).disposed(by: bag)
        
        search.map { "\($0.temperature)° C" }.drive(tempLabel.rx.text).disposed(by: bag)
        search.map { $0.icon }.drive(iconLabel.rx.text).disposed(by: bag)
        search.map { "\($0.humidity)%" }.drive(humidityLabel.rx.text).disposed(by: bag)
        search.map { $0.cityName }.drive(cityNameLabel.rx.text).disposed(by: bag)
        search.map { [$0.overlay()] }.drive(mapView.rx.overlays).disposed(by: bag)
        
        mapView
            .rx.setDelegate(self)
            .disposed(by: bag)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        Appearance.applyBottomLine(to: searchCityName)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Style
    private func style() {
        view.backgroundColor = UIColor.aztec
        searchCityName.textColor = UIColor.ufoGreen
        tempLabel.textColor = UIColor.cream
        humidityLabel.textColor = UIColor.cream
        iconLabel.textColor = UIColor.cream
        cityNameLabel.textColor = UIColor.cream
    }
}

extension ViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let overlay = overlay as? ApiController.Weather.Overlay {
            return ApiController.Weather.OverlayView(overlay: overlay, overlayIcon: overlay.icon)
        }
        return MKOverlayRenderer()
    }
    
}

