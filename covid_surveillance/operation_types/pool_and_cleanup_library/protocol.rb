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

needs 'Kits/KitContents'

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
  include CovidSurveillanceHelper
  include KitContents

 #========== Composition Definitions ==========#

  STAGED_POOLED_PLATE = 'Pooling Plate'.freeze
  KIT_SAMPLE_NAME = 'Library Pooling Kit'
  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 4.58, units: MICROLITERS,
         sample_name: nil,
         object_type: nil,
         notes: 'na'
       },
       {
         input_name: WATER,
         qty: 24, units: MICROLITERS,
         sample_name: WATER,
         object_type: 'Reagent Bottle',
         notes: 'na'
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
        input_name: MICRO_TUBE,
        qty: 2, units: 'Tubes',
        description: '1.7 ml Tube'
      },
      {
        input_name: SPARE_PLATE,
        qty: 2, units: 'Each',
        description: SPARE_PLATE
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
    mosquito_robot_program: 'Anneal RNA and FS Synthesis',
    mosquito_robot_model: Mosquito::MODEL,
    re_transfer_volume: create_qty(qty: 50, units: MICROLITERS),
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

    operations.make

    operations.each do |op|
      set_up_test(op) if debug

      temporary_options = op.temporary[:options]

      plate = op.input(POOLED_PLATE).collection
      output_pool = 'Wash Tube'
      output_tube = op.output('Pooled Library').item

      required_reactions = create_qty(qty: plate.parts.length + 2,
                                      units: 'rxn')

      composition, kit = setup_kit_composition(
        kit_sample_name: KIT_SAMPLE_NAME,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumables
      )

      composition.input(POOLED_PLATE).item = plate

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).object_type
      )
      
      retrieve_items = reject_components(
        list_of_rejections: [POOLED_PLATE],
        components: composition.components
      )

      adjust_volume(components: retrieve_items,
                    multi: required_reactions[:qty])

      show_retrieve_parts(retrieve_items + composition.consumables)

      vortex_list = [composition.input(ITB), composition.input(RSB_HT)]
  
      show_block_1a = (shake(items: vortex_list,
                                 type: Vortex::NAME))


      show_block_1b = prepare_etoh(comp: composition.input(ETOH), water: composition.input(WATER))

      show_block_1c = place_on_magnet(plate, time_min: 3)
      show_block_1d = spin_down(
        items: [plate],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      )
      show_block_1e = label_items(objects: [composition.input(MICROLITERS),
                                            composition.input(MICROLITERS),
                                            composition.input(POOLED_PLATE)],
                                  labels: [output_pool, output_tube, STAGED_POOLED_PLATE])
      show do
        title 'Prepare Components'
        note show_block_1a
        separator
        note show_block_1b
        separator
        note show_block_1c
        separator
        note show_block_1d
        separator
        note show_block_1e
      end

      mosquito_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_robot_program]
      )

      mosquito_robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:mosquito_robot_model],
        protocol: self
      )

      show_block_2a = use_robot(
        program: mosquito_program,
        robot: mosquito_robot,
        items: [composition.input(SPARE_PLATE),
                composition.input(POOLED_PLATE).item]
      )

      show_block_2b = pipet(volume: {qty: 55, units: MICROLITERS},
                            source: STAGED_POOLED_PLATE,
                            destination: output_pool)

      show do
        title 'Pool Wells'
        note show_block_2a
        separator
        note show_block_2b
      end

      adjt_multi = plate.get_non_empty.length * 
                   composition.input(POOLED_PLATE).volume_hash[:qty] *
                   0.9
      adjust_volume(components: [composition.input(ITB)],
                    multi: adjt_multi)


      association_map = one_to_one_association_map(from_collection: plate)

      associate_transfer_collection_to_item(
        from_collection: plate,
        to_item: output_tube,
        association_map: association_map,
        transfer_vol: composition.input(POOLED_PLATE).volume_hash)

      show_block_3a = shake(
        items: [output_pool, composition.input(ITB)],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      )

      show_block_3b = pipet(
        volume: composition.input(ITB).volume_hash(adj_qty: true),
        source: composition.input(ITB),
        destination: output_pool
      )

      show_block_3c = shake(
        items: [output_pool],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      )

      show_block_3d =show_incubate_items(
        items: [output_pool],
        time: temporary_options[:incubation_params][:time],
        temperature: temporary_options[:incubation_params][:temperature]
      )

      show_block_3e = spin_down(
        items: [output_pool],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      )

      show_block_3f = place_on_magnet(output_pool, time_min: 5)

      show_block_3g = remove_discard_supernatant([output_pool])

      show_block_3h = wash_beads(output_tube)

      show_block_3i = wash_beads(output_tube)


      show_block_3j = pipet(
        volume: composition.input(RSB_HT).volume_hash(adj_qty: true),
        source: composition.input(RSB_HT),
        destination: output_pool
      )



      show_block_3k = shake(
        items: [output_pool],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      )

      show_block_3l =spin_down(
        items: [output_pool],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      )

      show_block_3m =show_incubate_items(
        items: [output_pool],
        time: temporary_options[:incubation_params][:time],
        temperature: temporary_options[:incubation_params][:temperature]
      )

      show_block_3n = place_on_magnet(output_pool, time_min: 2)

      show_block_3o = pipet(volume: temporary_options[:re_transfer_volume],
                            source: output_pool,
                            destination: output_tube)

      show do
        title 'Clean up Library (1:3)'
        note show_block_3a
        separator
        note show_block_3b
        separator
        note show_block_3c
        separator
        note show_block_3d
      end

      show do
        title 'Clean up Library (2:3)'
        note show_block_3e
        separator
        note show_block_3f
        separator
        note show_block_3g
        separator
        note show_block_3h
        separator
        note show_block_3i
        separator
      end

      show do
        title 'Clean up Library Continued (3:3)'
        note show_block_3j
        separator
        note show_block_3k
        separator
        note show_block_3l
        separator
        note show_block_3m
        separator
        note show_block_3n
        separator
        note show_block_3o
      end

    end

    {}
  end

  # Directions to wash beads
  #
  # @param output_tube [composition]
  def wash_beads(output_tube)
    show_block = [
      "Place #{output_tube} on the magnetic stand and add 1000 µl fresh 80% EtOH",
      'Wait for 30 Seconds'
    ]

    show_block + remove_discard_supernatant([output_tube])
  end

  # Instructions to prepare EtOH
  #
  # @param comp [Component] the EtOH component
  def prepare_etoh(comp:, water:)
    total_vol = comp.volume_hash(adj_qty: true)
    oh_vol = create_qty(qty: total_vol[:qty] * 0.8, units: total_vol[:units])
    water_vol = create_qty(qty: total_vol[:qty] * 0.2, units: total_vol[:units])

    show_block = ["Prepare 80% EtOH from Absolute EtOH #{comp.item}"]
    show_block.append(pipet(volume: oh_vol,
                            source: comp, destination: 'reagent bottle'))
    show_block.append(pipet(volume: water_vol,
                            source: water, destination: 'reagent bottle'))
    show_block
  end


  # sets up the test
  #
  # @param op [Operation]
  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)
  end

end
