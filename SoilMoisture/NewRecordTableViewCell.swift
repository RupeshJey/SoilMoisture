//
//  NewRecordTableViewCell.swift
//  SoilMoisture
//
//  Created by Rupesh Jeyaram on 4/4/17.
//  Copyright © 2017 Planlet Systems. All rights reserved.
//

import UIKit

class NewRecordTableViewCell: UITableViewCell {

    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var detail: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
