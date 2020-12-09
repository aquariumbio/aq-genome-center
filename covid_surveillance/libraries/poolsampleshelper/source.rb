# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Collection Management/CollectionActions'
needs 'Covid Surveillance/PoolingHelper'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/ManualPoolingHelper'
needs 'Barcodes/BarcodeHelper'
needs 'Microtiter Plates/MicrotiterPlates'

module PoolSamplesHelper
  include PlanParams
  include Debug
  include AssociationKeys
  include PoolingHelper
  include BarcodeHelper
  include ManualPoolingHelper
  include CollectionActions
  include MicrotiterPlates

  # Validates operations
  #   - Checks whether any operation has too many input specimens
  #
  # @param operations [OperationList]
  # @param max_specimens [FixNum] the max number of specimens per operation
  # @return void
  def validate(operations:, max_specimens:)
    cts = []
    operations.each do |op|
      n_specimens = op.input_array(SPECIMEN).length
      cts.append(n_specimens)
      next unless n_specimens > max_specimens

      msg = "operation has #{n_specimens} specimens when only #{max_specimens} are allowed"
      op.error(:input_error, msg)
      show do
        title 'Job failed validation'
        note "Operation #{op.id} failed validation because it has too many inputs."
        warning 'This job will terminate early.'
      end
    end

    return if cts.uniq.length == 1

    msg = "operations have unequal numbers of inputs #{cts}"
    operations.each { |op| op.error(:input_error, msg) }
    show do
      title 'Job failed validation'
      note 'This protocol requires all the opertations to have the same number of inputs.'
      warning 'This job will terminate early.'
    end
  end

  # Collects a flat array of input specimen items from the provided operations
  #
  # @param operations [OperationList]
  # @return [Array<Item>]
  def collect_specimens(operations:)
    operations.map { |op| op.input_array(SPECIMEN).map(&:item) }.flatten
  end

  # Creates a new collection using CollectionActions#make_new_plate
  #   and sets the collection as the output for the provided operations
  # @todo setting the same sample for all the wells is probably misleading
  #
  # @param sample [Sample] sample that is added to all wells in the collection
  # @param operations [OperationList] the operations that the collection will
  #   be added to
  # @return [Collection] the new collection
  def create_output_collection(sample:, operations:)
    collection = make_new_plate(PLATE_OBJECT_TYPE, label_plate: true)
    size = collection.dimensions.reduce(:*)
    collection.add_samples(Array.new(size, sample))
    operations.each { |op| op.output(POOLED_PLATE).set(collection: collection) }
    collection
  end

  # Creates a new MicrotiterPlate to wrap the provided collection and adds
  #   the provided pooling groups to the collections provenance map
  #
  # @param collection [Collection]
  # @param pooling_groups [Array<Item>]
  # @return [MicrotiterPlate]
  def add_pools(collection:, pooling_groups:)
    microtiter_plate = MicrotiterPlateFactory.build(
      collection: collection,
      group_size: 1,
      method: :row_wise
    )
    add_provenance(
      microtiter_plate: microtiter_plate,
      pooling_groups: pooling_groups
    )
  end

  private

  # Adds the provided pooling groups to the provenance map of
  #   the MicrotiterPlate
  #
  # @param microtiter_plate [MicrotiterPlate]
  # @param pooling_groups [Array<Item>]
  # @return [MicrotiterPlate]
  def add_provenance(microtiter_plate:, pooling_groups:)
    pooling_groups.each do |pooling_group|
      microtiter_plate.associate_provenance_next_empty(
        key: :specimens,
        data: pooling_group.map { |item| hash_data(item) }
      )
    end
    microtiter_plate
  end

  # Creates a provenance hash for the provided item
  #
  # @param item [Item]
  # @return [Hash]
  def hash_data(item)
    properties = item.sample.properties
    default = 'not found'
    specimen_barcode = properties.fetch('Specimen Barcode', default)
    rack_barcode = properties.fetch('Rack Barcode', default)
    rack_location = properties.fetch('Rack Location', default)
    {
      item: item,
      specimen_barcode: specimen_barcode,
      rack_barcode: rack_barcode,
      rack_location: rack_location
    }
  end

  def inspect_first_three(collection)
    3.times do |i|
      inspect_provenance(
        collection: collection,
        row: 0,
        col: i
      )
    end
  end

  def inspect_provenance(collection:, row:, col:)
    part = collection.part(row, col)
    inspect part, "part at #{[row, col]}"
    inspect part.associations, "associations at #{[row, col]}"
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
