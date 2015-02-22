require "rubygems"
require "time"
require "json"
require "fog"
require "clockwork"
require "mackerel"

include Clockwork

class Price
  attr_reader :hourly, :monthly
  def initialize(hourly, monthly)
    @hourly, @monthly = hourly, monthly
  end

  def +(p)
    Price.new(@hourly + p.hourly, @monthly + p.monthly)
  end

  def *(x)
    Price.new(@hourly * x, @monthly * x)
  end
end

@monitoring_interval = ENV["MONITORING_INTERVAL"].to_i

@cloudstack = Fog::Compute.new(
  :provider                     => "cloudstack",
  :cloudstack_scheme            => "https",
  :cloudstack_host              => "compute.jp-east.idcfcloud.com",
  :cloudstack_path              => "/client/api",
  :cloudstack_port              => 443,
  :cloudstack_api_key           => ENV["CLOUDSTACK_API_KEY"],
  :cloudstack_secret_access_key => ENV["CLOUDSTACK_SECRET_ACCESS_KEY"],
)

@mackerel = Mackerel::Client.new(:mackerel_api_key => ENV["MACKEREL_API_KEY"])
@mackerel_service_name = ENV["MACKEREL_SERVICE_NAME"]

@vm_price = {
  "light.S1"      => Price.new(0.4,    200),
  "light.S2"      => Price.new(6.6,   3200),
  "standard.S4"   => Price.new( 11,   5300),
  "standard.M8"   => Price.new( 30,  14500),
  "standard.L16"  => Price.new( 60,  29000),
  "standard.XL32" => Price.new(120,  58000),
  "highcpu.M4"    => Price.new( 19,   9200),
  "highcpu.L8"    => Price.new( 38,  18300),
  "highcpu.XL16"  => Price.new( 76,  36600),
  "highcpu.2XL32" => Price.new(152,  73200),
  "highmem.M16"   => Price.new( 31,  15000),
  "highmem.L32"   => Price.new( 62,  30000),
  "highmem.XL64"  => Price.new(124,  60000),
  "highio.5XL128" => Price.new(370, 179000),
}

@volume_price  = Price.new(0.04,    20)
@archive_price = Price.new(0.06,    30)
@network_price = Price.new(  20, 10000)
@pubip_price   = Price.new(   1,   500)

def calc_current_price

  current_price = Price.new(0, 0)

  @cloudstack.servers.each do |vm|
    if vm.state == "Running" or vm.flavor_name.start_with?("highio")
      current_price += @vm_price[vm.flavor_name]
    end
  end

  @cloudstack.volumes.each do |volume|
    current_price += @volume_price * (volume.size / 1024 / 1024 / 1024)
  end

  @cloudstack.images.all("templatefilter" => "self").each do |image|
    current_price += @archive_price * (image.size / 1024 / 1024 / 1024)
  end

  (@cloudstack.list_isos["listisosresponse"]["iso"] || []).each do |iso|
    current_price += @archive_price * (iso["size"] / 1024 / 1024 / 1024)
  end

  @cloudstack.snapshots.each do |snapshot|
    volume = @cloudstack.volumes.all(id=snapshot.volume_id).first
    current_price += @archive_price * (volume.size / 1024 / 1024 / 1024)
  end

  @cloudstack.networks.each do |network|
    if network.type != "Isolated"
      current_price += @network_price
    end
  end

  current_price += @pubip_price * 
    [@cloudstack.public_ip_addresses.length - 1, 0].max

  current_price
end

every(@monitoring_interval.seconds, "idcfcloud-billing-monitor") do
  t = Time.now.to_i
  p = calc_current_price
  puts @mackerel.post_service_metrics(@mackerel_service_name, [
    {:name  => "billing.hourly",  :time  => t, :value => p.hourly},
    {:name  => "billing.monthly", :time  => t, :value => p.monthly},
  ])
end
