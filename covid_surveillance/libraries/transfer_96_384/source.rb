needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Standard Libs/Units'
needs 'Standard Libs/CommonInputOutputNames'
needs 'Standard Libs/AssociationManagement'

needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'

needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionActions'
needs 'Collection Management/CollectionTransfer'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'Kits/KitContents'

module Transfer_96_384

  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CommonInputOutputNames
  include CompositionHelper
  include CollectionActions
  include CollectionTransfer
  include RunThermocycler
  include KitHelper
  include CovidSurveillanceHelper
  include KitContents
  include AssociationManagement

  def transfer_96_to_384(op, components, plate_name_array, plate_transfer_map)
    input_plates = plate_name_array.map{ |ip| op.input(ip).collection }
    set_up_test(input_plates) if debug

    composition = CompositionFactory.build(
      components: components
    )
    composition.input(POOLED_PLATE).item = op.output(POOLED_PLATE).collection
    plate_name_array.each do |name|
      composition.input(name).item = op.input(name).collection
    end

    temporary_options = op.temporary[:options]

    # SHOW gets the parts in the composition
    show_retrieve_parts(composition.components) # and consumables

    program = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:tr_96_384_program]
    )

    robot = LiquidRobotFactory.build(
      model: temporary_options[:tr_96_384_robot],
      name: nil,
      protocol: nil
    )

    display_hash(
      title: 'Set Up and Run Robot',
      hash_to_show: use_robot(program: program,
                              robot: robot,
                              items: [composition.input(plate_name_array),
                                      composition.input(POOLED_PLATE)].flatten)
    )

    transfer_provenance(plate_transfer_map,
                        pooled_plate: POOLED_PLATE,
                        comp: composition)
  end

  # Sets up test plates for tests runs
  def set_up_test(input_plates)
    input_plates.each do |plate|
      sample = plate.parts.first.sample
      plate.add_samples(Array.new(plate.get_empty.length, sample))
    end
  end

  # Handles the provenance for the 96 to 384 transfer
  #
  # @param plate_transfer_map
  def transfer_provenance(plate_transfer_map, pooled_plate:, comp:)
    output_plate = comp.input(pooled_plate).item
    plate_transfer_map.each do |quad|
      input_plate = comp.input(quad[:plate]).item

      row_limit = quad[:rows][1]
      column_limit = quad[:columns][1]

      input_plate.get_non_empty.each do |loc|
        target_row = loc[0] + quad[:rows][0]
        target_column = loc[1] + quad[:columns][0]
        if target_row > row_limit || target_column > column_limit
          raise 'Row or column outside of quadrant limit'
        end

        from_part = input_plate.part(loc[0], loc[1])
        output_plate.set(target_row, target_column, from_part.sample)
        to_part = output_plate.part(target_row, target_column)

        from_obj_to_obj_provenance(from_item: from_part, to_item: to_part)
      end
    end
  end

end