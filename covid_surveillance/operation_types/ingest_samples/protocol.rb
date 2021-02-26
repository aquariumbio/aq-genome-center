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
needs 'CompositionLibs/CompositionHelper'

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
      default_sample_type: 'Nasal swab'
    }
  end

  EXAMPLE_CSV = [
    ['Plate ID/barcode', 'Well  Position', 'Sample ID', 'Sample Volume (ul)',
     'Sample type', 'Sample Week', "'Age Range"],
    ['FSH006Y5', 'A01', 'MN0-0105', '150', 'Nasal swab', '6', '18-27'],
    ['FSH006Y5', 'A02', 'MN0-01VG', '150', 'Nasal swab', '6', '18-27'],
    ['FSH006Y5', 'A03', 'MN0-0166', '150', 'Nasal swab', '6', '18-27']
  ]


  def main

    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.make

    operations.each do |op|
      output_plate = op.output(POOLED_PLATE).collection

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
        sample_volume = row[3]
        sample_type = row[4]
        sample_week = row[5]
        sample_age_range = row[6]
        new_sample = nil

        incoming_plate_identifier = plate_id if incoming_plate_identifier.nil?

        unless incoming_plate_identifier = plate_id
          raise 'CSV is for more than one incoming plate'
        end

        unless sample_type.present?
          sample_type = temporary_options[:default_sample_type]
        end

        if Sample.find_by_name(sample_name).present?
          new_sample = Sample.find_by_name(sample_name)
        else
          new_sample = Sample.creator(
            {
              sample_type_id: SampleType.find_by_name(sample_type).id,
              description: "A Sample generated from 'Ingest Samples",
              name: sample_name,
              project: temporary_options[:project],
              field_values: [
                { name: 'Initial Well Location', value: well },
                { name: 'Incoming Plate ID', value: plate_id },
                { name: 'Sample Week', value: sample_week },
                { name: 'Sample Age Range', value: sample_age_range },
                { name: 'Initial Volume (ul)', value: sample_volume }
              ]
            }, User.find(1)
          )
        end

        r, c = convert_location_to_coordinates(well)

        inspect "#{well}, #{r}, #{c}"
        unless output_plate.part(r, c).nil?
          raise "collection location already full #{r}, #{c}"
        end

        output_plate.set(r, c, new_sample)
      end

      show_block1 = [
        {
          display: label_items(objects: [incoming_plate_identifier],
                               labels: [output_plate]),
          type: 'note'
        }
      ]

      display_hash(
        title: 'Ingest Plate',
        hash_to_show: show_block1
      )


    end

    {}

  end
end
