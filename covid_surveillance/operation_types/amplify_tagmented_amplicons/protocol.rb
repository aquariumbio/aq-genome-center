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

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Kits/KitContents'

needs 'ConsumableLibs/Consumables'

needs 'ConsumableLibs/ConsumableDefinitions'

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
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

 #========== Composition Definitions ==========#
  AMP_TAG_KIT = 'Amplify Tagmented Amplicons Kit'
  IDT_PLATE = 'Index Adapter'
  SPARE_PLATE = '96 Well Plate'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: PLATE_384_WELL
       },
       {
         input_name: WATER,
         qty: 24, units: MICROLITERS,
         sample_name: WATER,
         object_type: 'Reagent Bottle'
      },
      {
        input_name: MASTER_MIX,
        qty: 20, units: MICROLITERS,
        sample_name: MASTER_MIX,
        object_type: TEST_TUBE
      },
      {
        input_name: IDT_PLATE,
        qty: 10, units: MICROLITERS,
        sample_name: IDT_PLATE,
        object_type: PLATE_384_WELL
      }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[SPARE_PLATE],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TIP_BOX_100],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TEST_TUBE],
        qty: 1, units: 'Tubes'
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
    mosquito_remove_robot_program: 'Amplify Tagmented Amplicons',
    transfer_index_program: 'Amplify Tagmented Amplicons Index Plate',
    mosquito_transfer_index_program: 'PCR_MM',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'EP3_HT',
    dragonfly_robot_model: Dragonfly::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'CDC_TaqPath_CG',
    qpcr: true
  }
end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.each do |op|
      set_up_test(op) if debug
      op.pass(POOLED_PLATE)

      temporary_options = op.temporary[:options]


      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_name: AMP_TAG_KIT,
        num_reactions_required: op.input(POOLED_PLATE).collection.parts.length,
        components: components,
        consumables: consumable_data
      )

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      composition.input(IDT_PLATE).item = op.input(IDT_PLATE).collection

      plate = composition.input(POOLED_PLATE).item
      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).object_type
      )

      mm = composition.input(MASTER_MIX)
      adj_multi = plate.get_non_empty.length
      mm_components = [composition.input(EPM_HT),
                       composition.input(WATER)]

      adjust_volume(components: mm_components,
                    multi: adj_multi)

      mm.item = make_item(sample: mm.sample,
                          object_type: mm.object_type)

      retrieve_list = reject_components(
        list_of_rejections: [MASTER_MIX, POOLED_PLATE],
        components: composition.components
      )
      show_retrieve_parts(retrieve_list + consumables.consumables)

      vortex_list = reject_components(
        list_of_rejections: [WATER, IDT_PLATE],
        components: retrieve_list
      )
      show_block_1 = []
      show_block_1.append(
        { display: shake(items: vortex_list,
                         type: Vortex::NAME),
          type: 'note' }
      )

      adj_multiplier = plate.get_non_empty.length
      mm_components = [composition.input(EPM_HT), composition.input(WATER)]

      show_block_1.append({
        display: master_mix_handler(components: mm_components,
                                    mm: composition.input(MASTER_MIX),
                                    adjustment_multiplier: adj_multiplier,
                                    mm_container: composition.input(TEST_TUBE)),
        type: 'note'
      })

      show_block_1.append({ display: place_on_magnet(plate), type: 'note' })

      mosquito_robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      drgrobot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      remove_supernatant_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_remove_robot_program]
      )

      show_block_1.append(
        use_robot(program: remove_supernatant_program,
                  robot: mosquito_robot,
                  items: [plate])
      )

      add_mm_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program]
      )

      show_block_1.append(
        use_robot(program: add_mm_program,
                  robot: drgrobot,
                  items: [plate, composition.input(MASTER_MIX)])
      )


      index_transfer_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_transfer_index_program]
      )

      show_block_1.append(
        use_robot(program: index_transfer_program,
                  robot: mosquito_robot,
                  items: [plate, composition.input(IDT_PLATE)])
      )
      association_map = one_to_one_association_map(from_collection: plate)

      associate_transfer_item_to_collection(
        from_item: mm.item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: mm.volume_hash
      )

      associate_transfer_collection_to_collection(
        from_collection: composition.input(IDT_PLATE).item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: composition.input(IDT_PLATE).volume_hash
      )

      transfer_adapter_index(from_plate: plate,
                             to_plate: composition.input(IDT_PLATE).item)

      show_block_2 = []
      show_block_2.append(
        {
          display: seal_plate(
            [plate], seal: consumables.input(AREA_SEAL)
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: shake(
            items: [plate],
            speed: temporary_options[:shaker_parameters][:speed],
            time: temporary_options[:shaker_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: spin_down(
            items: [plate],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: pipet_up_and_down(plate),
          type: 'note'
        }
      )

      display_hash(
        title: 'Prep and Run Robot',
        hash_to_show: show_block_1
      )

      display_hash(
        title: 'Prepare for Thermocycler',
        hash_to_show: show_block_2
      )

      run_qpcr(op: op,
               plates: [plate])
    end

    {}

  end

  def transfer_adapter_index(from_plate:, to_plate:)
    from_plate.parts.zip(to_plate.parts).each do |from, to|
      skip if from.nil? || to.nil?
      to_plate.associate(INDEX_KEY, from.get(INDEX_KEY))
    end
  end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)

    sample = op.input(IDT_PLATE).part.sample
    plate = op.input(IDT_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)

    op.input(IDT_PLATE).collection.parts.each do |part|
      part.associate(INDEX_KEY, [1,2,3,4].sample)
    end
  end

end