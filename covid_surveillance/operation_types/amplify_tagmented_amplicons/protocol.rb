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
needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'


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


#========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  AMP_TAG_KIT = 'Amplify Tagmented Amplicons Kit'

  EPM_HT = 'Enhanced PCR Mix HT'
  IDT_PLATE = 'Index Adapter Plate'
  WATER = 'Nuclease-free water'

  TEST_TUBE = '15 ml Tube'

  SPARE_PLATE = '96 Well Plate'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
         input_name: WATER,
         qty: 24, units: MICROLITERS,
         sample_name: WATER,
         object_type: 'Reagent Bottle'
      }
    ]
  end

  def consumables
    [
      {
        input_name: AREA_SEAL,
        qty: 1, units: 'Each',
        description: 'Adhesive Plate Seal'
      },
      {
        input_name: SPARE_PLATE,
        qty: 1, units: 'Each',
        description: '96 Well PCR Plate'
      },
      {
        input_name: 'pipet_tip_100',
        qty: 2, units: 'Box',
        description: '100 ul Pipet Tips'
      },
      {
        input_name: TEST_TUBE,
        qty: 1, units: 'Tubes',
        description: '15 ml Tube'
      }
    ]
  end

  def kits
    [
      {
        input_name: AMP_TAG_KIT,
        qty: 1, units: 'kits',
        description: 'Kit for amplifying tagmented amplicons',
        location: 'M80 Freezer',
        components: [
          {
            input_name: EPM_HT,
            qty: 24, units: MICROLITERS,
            sample_name: EPM_HT,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: IDT_PLATE,
            qty: 10, units: MICROLITERS,
            sample_name: IDT_PLATE,
            object_type: '96-Well Plate'
          }
        ],
        consumables: [
        ]
      }
    ]
  end

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
    robot_program: 'abstract program',
    instrument_model: TestLiquidHandlingRobot::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') }
  }
end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    paired_ops = pair_ops_with_instruments(operations: operations,
                                           instrument_key: LIQUID_ROBOT_PARAM)

    remove_unpaired_operations(operations - paired_ops)

    paired_ops.each do |op|
      set_up_test(op) if debug
      op.input(IDT_PLATE).collection.associate(INDEX_KEY, [1,2,3,4].sample) if debug
      op.pass(POOLED_PLATE)

      date = DateTime.now.strftime('%Y-%m-%d')
      file_name = "#{date}_Op_#{op.id}_Plate_#{op.output(POOLED_PLATE).collection.id}"

      temporary_options = op.temporary[:options]

      composition = CompositionFactory.build(components: components,
                                             consumables: consumables,
                                             kits: kits)

      program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:robot_program]
      )

      robot = LiquidRobotFactory.build(model: temporary_options[:instrument_model],
                                       name: op.temporary[INSTRUMENT_NAME],
                                       protocol: self)

      unless check_robot_compatibility(input_object: op.input(POOLED_PLATE).collection,
                                       robot: robot,
                                       program: program)
        remove_unpaired_operations([op])
        next
      end

      kit = composition.input(AMP_TAG_KIT)

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      kit.input(IDT_PLATE).item = op.input(IDT_PLATE).collection

      plate = composition.input(POOLED_PLATE).item
      op.pass(POOLED_PLATE)
      composition.find_component_items
      composition.make_kit_component_items

      adjt_multi = plate.get_non_empty.length
      adj_comp = [kit.input(EPM_HT), composition.input(WATER)]
      adjust_volume(components: adj_comp,
                    multi: adjt_multi)

      show_get_composition(composition: composition)

      retrieve_materials([plate])

      show_thaw_items(kit.composition.components.map(&:input_name))

      vortex_objs(kit.composition.components.map(&:input_name))

      open_index_adapter_plate(index_plate: composition.input(AMP_TAG_KIT).input(IDT_PLATE),
                               pcr_plate: composition.input(SPARE_PLATE))

      create_master_mix(components: adj_comp, vessel: composition.input(TEST_TUBE))

      place_on_magnet(plate)

      remove_discard_supernatant([plate])

      remove_from_magnet(plate)

      robot.turn_on

      go_to_instrument(instrument_name: robot.model_and_name)

      robot.select_program_template(program: program)

      robot.save_run(path: program.run_file_path, file_name: file_name)

      robot.follow_template_instructions

      wait_for_instrument(instrument_name: robot.model_and_name)

      robot.remove_item(item: plate)

      association_map = one_to_one_association_map(from_collection: plate)

      associate_transfer_item_to_collection(
        from_item: kit.input(EPM_HT).item,
        to_collection: plate,
        association_map: association_map
      )

      associate_transfer_item_to_collection(
        from_item: composition.input(WATER).item,
        to_collection: plate,
        association_map: association_map
      )

      associate_transfer_collection_to_collection(
        from_collection: kit.input(IDT_PLATE).item,
        to_collection: plate,
        association_map: association_map
      )

      plate.associate(INDEX_KEY, kit.input(IDT_PLATE).item.get(INDEX_KEY))

      seal_plate(plate, seal: composition.input(AREA_SEAL).input_name)

      shake(items: [plate],
            speed: temporary_options[:shaker_parameters][:speed],
            time: temporary_options[:shaker_parameters][:time])

      spin_down(items: [plate],
                speed: temporary_options[:centrifuge_parameters][:speed],
                time: temporary_options[:centrifuge_parameters][:time])

      pipet_up_and_down(plate)

      store_items([plate], location: temporary_options[:storage_location])
    end

    {}
  end

  # Instruction to pipet up and down to mix
  #
  # @param plate [Collection]
  def pipet_up_and_down(plate)
    show do
      title 'Pipet up and down to Mix'
      note 'Set Pipet to 35 ul'
      note "Pipet up and down to mix all wells of plate #{plate}"
    end
  end

  # Instructions to place plate on some magnets
  #
  # @param plate [Collection]
  def place_on_magnet(plate)
    show do
      title 'Place on Magnetic Stand'
      note "Put plate #{plate} on magnetic stan"
      note 'Keep on magnet for the next few steps'
    end
  end

  # Instructions to remove plate from magnet
  #
  # @param plate [Collection]
  def remove_from_magnet(plate)
    show do
      title 'Remove from Magnetic Stand'
      note "Remove plate #{plate} from magnetic stan"
    end
  end

  # Instructions on how to open index plate
  #
  # @param index_plate [Component] Tee plate to be opened
  # @param pcr_plate [Consumable] Plate to help open index plate
  def open_index_adapter_plate(index_plate:, pcr_plate:)
    show do
      title 'Open Index Adapter Plate'
      note "Align a new #{pcr_plate.input_name} above index plate #{index_plate.input_name} and press down to puncture the foil seal"
      note "Discard #{pcr_plate.input_name}"
    end
  end

  def set_up_test(op)
    [POOLED_PLATE, IDT_PLATE].each do |nam|
      sample = op.input(nam).part.sample
      plate = op.input(nam).collection
      samples = Array.new(plate.get_empty.length, sample)
      plate.add_samples(samples)
    end
  end

end
