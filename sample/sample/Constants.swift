//
//  Constants.swift
//  ObservationLearning
//
//  Created by differenz53 on 25/09/24.
//

import Foundation


enum apiUrl: String {
    case brand
    case user
    case todos
    
    var route: String {
        get {
            switch self {
                
            case .brand:
                "https://random-data-api.com/api/v2/appliances?size=10#"
            case .user:
                "https://jsonplaceholder.typicode.com/users"
            case .todos:
                "https://jsonplaceholder.typicode.com/todos"
            }
        }
    }
    
}
