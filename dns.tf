#  Copyright 2018-2019 Spotify AB.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.

data "aws_route53_zone" "web_dns_domain" {
  zone_id = var.web_dns_zone_id
}

resource "aws_route53_record" "cname_route53_record" {
  zone_id = var.web_dns_zone_id
  type    = "A"
  name    = var.grr_frontend_sub_domain

  alias {
    name                   = "${aws_lb.demo-alb.dns_name}"
    zone_id                = "${aws_lb.demo-alb.zone_id}"
    evaluate_target_health = false
  }
}
