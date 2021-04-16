# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Small Instruments/Centrifuges'
needs 'Small Instruments/Shakers'
needs 'Standard Libs/Units'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'
needs 'Liquid Robot Helper/RobotHelper'

needs 'Composition Libs/Composition'
needs 'Composition Libs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

require 'csv'
require 'open-uri'

class Protocol

  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Centrifuges
  include Shakers
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CompositionHelper
  include CollectionTransfer
  include CollectionActions
  include RunThermocycler
  include KitHelper
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions
  
  POOLED_PLATE = 'Sample Plate'

  def components_data
    []
  end

  def consumable_data
    [
    ]
  end

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
      project: 'Covid Surveillance',
      default_sample_type: 'Index Adapter Sample'
    }
  end

  EXAMPLE_CSV = [
    ['Plate ID/barcode', 'Well  Position', 'Index Sequence'],
    ['FSH006Y5', 'A01', 'ACTGTCC'],
    ['FSH006Y5', 'A02', 'ACGTCCC'],
    ['FSH006Y5', 'A03', 'TGTTCCA']
  ]


  def main

    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.each do |op|
      output_plate = Collection.new_collection(ObjectType.find_by_name('96-Well Plate'))
      op.output('Sample Plate').set(item: output_plate)

      temporary_options = op.temporary[:options]

      parsed_csv = nil
      if debug
        parsed_csv = EXAMPLE_CSV
      else
        sample_csv = uploadData('Sample Plate CSV', 1, 10).first
        open(sample_csv.expiring_url) do |sample_io|
          parsed_csv = CSV.read(sample_io)
        end
      end

      incoming_plate_identifier = nil
      parsed_csv.drop(1).each do |row|
        plate_id = row[0]
        well = row[1]
        sample_name = row[2]
        new_sample = nil

        incoming_plate_identifier = plate_id if incoming_plate_identifier.nil?

        unless incoming_plate_identifier = plate_id
          raise 'CSV is for more than one incoming plate'
        end

        sample_type = temporary_options[:default_sample_type]

        if Sample.find_by_name(sample_name).present?
          new_sample = Sample.find_by_name(sample_name)
        else
          new_sample = Sample.creator(
            {
              sample_type_id: SampleType.find_by_name(sample_type).id,
              description: "A Sample generated from 'Ingest Index Plates'",
              name: sample_name,
              project: temporary_options[:project],
              field_values: [
                { name: 'Initial Well Location', value: well },
                { name: 'Incoming Plate ID', value: plate_id },
              ]
            }, User.find(1)
          )
        end

        r, c = convert_location_to_coordinates(well)

        unless output_plate.part(r, c).nil?
          raise "collection location already full #{r}, #{c}"
        end

        output_plate.set(r, c, new_sample)
      end

      display(
        title: 'Ingest Plate',
        show_block: label_items(objects: [incoming_plate_identifier],
                                labels: [output_plate])
      )


    end

    {}

  end
end
