# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/UploadHelper'
needs 'Standard Libs/Units'
needs 'Standard Libs/ItemActions'
needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionDisplay'
needs 'Covid Surveillance/PoolingHelper'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Tube Rack/TubeRackHelper'
needs 'Tube Rack/TubeRack'
needs 'Barcodes/BarcodeHelper'

class Protocol
  include PlanParams
  include Debug
  include UploadHelper
  include Units
  include ItemActions
  include AssociationKeys
  include SampleConstants
  include PoolingHelper
  include BarcodeHelper
  include TubeRackHelper


  ########## DEFAULT PARAMS ##########

  # Default parameters that are applied equally to all operations.
  #   Can be overridden by:
  #   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_job_params
    {
    }
  end

  # Default parameters that are applied to individual operations.
  #   Can be overridden by:
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_operation_params
    {
      pooling_method: 'Standard',
      sample_rack: { dimensions: [1,10], name: 'Specimen Rack'},
      transfer_volume: { qty: 5, units: MICROLITERS },
      plate_location: 'M20'
    }
  end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )
    return {} if operations.errored.any?

    operations.make

    operations.retrieve
    if operations.any?{ |op| op.input_array(SPECIMEN).length > 960 }
      raise 'too many inputs' 
    end
 
    operations.each do |op|

      pooling_groups = create_pooling_groups(
        items: debug ? setup_test(op) : op.input_array(SPECIMEN).map(&:item),
        pooling_method: op.temporary[:options][:pooling_method]
      )
      rack_info = op.temporary[:options][:sample_rack]
      max_samples = rack_info[:dimensions][0] * rack_info[:dimensions][1]

      group_by_size(pooling_groups, max_samples).each do |sized_pooling_group|
        sample_rack = TubeRack.new(rack_info[:dimensions][0],
                                  rack_info[:dimensions][1],
                                  name: rack_info[:name])
        show_fetch_tube_rack(sample_rack)

        decap_and_add_to_rack(pooling_groups: sized_pooling_group,
                              tube_rack: sample_rack)

        add_samples(pooling_groups: sized_pooling_group,
                    tube_rack: sample_rack,
                    plate: op.output(POOLED_PLATE).collection,
                    transfer_volume: op.temporary[:options][:transfer_volume],
                    sample_type: op.output(POOLED_PLATE).sample_type)
      end
      store_items([op.output(POOLED_PLATE).collection],
                  location: op.temporary[:options][:plate_location])
    end

    {}

  end

  def group_by_size(pooling_groups, max_samples)
    size_groups = []
    pooling_groups.each do |group|
      add_to_size_group(group, size_groups, max_samples)
    end
    size_groups
  end
  # size group = [[a,b,c], [a,b,c]]
  def add_to_size_group(group, size_groups, max_samples)
    added = false
    size_groups.each do |size_group|
      total_size = size_group.map(&:length).inject(0, :+)
      next if total_size + group.length > max_samples
      size_group.push(group)
      added = true
    end
    size_groups.push([group]) unless added
  end

  def add_samples(pooling_groups:, tube_rack:, plate:,
                  transfer_volume:, sample_type:)
    pooling_groups.each do |group|
      project = group.first.sample.project
      sample = Sample.creator(
        {
          sample_type_id: sample_type,
          description: "Pooled Specimen of items #{group.map(&:id)}",
          name: "Pooled Specimen #{group.map(&:id)}",
          project: project,
        }, User.find(1)
      )
      to_loc = plate.get_empty.first
      raise 'not enough space for all samples' if to_loc.nil?
      plate.set(to_loc[0], to_loc[1], sample)
      association_map = []
      group.each do|item| 
        association_map.push({to_loc: to_loc, from_loc: tube_rack.find(item)})
      end
      single_channel_collection_to_collection(to_collection: plate,
                                            from_collection: tube_rack,
                                            volume: transfer_volume,
                                            association_map: association_map)

      associate_transfer_collection_to_collection(from_collection: tube_rack,
                                                  to_collection: plate,
                                                  association_map: association_map,
                                                  transfer_vol: transfer_volume)
    end
  end

  def decap_and_add_to_rack(pooling_groups:, tube_rack:)
    pooling_groups.each do |group|
      group.each do |item|
        decap_vial(item)
        show_add_items([item], tube_rack)
      end
    end
  end

  def decap_vial(item)
    show do
      title 'Decap Vial'
      note "Remove cap from #{item.id}"
    end
  end

  def setup_test(op)
      sample = op.input_array(SPECIMEN).first.item.sample
      ot = op.input_array(SPECIMEN).first.item.object_type.name
      items = []

      5.times do
        items.push(sample.make_item(ot))
      end

      items.each do |item|
        add_random_barcode_id(item)
      end
    items
  end

end
